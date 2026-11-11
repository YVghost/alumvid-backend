package com.alumvid.ubicaciones;

import java.math.BigDecimal;
import java.util.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;

@Service
class UbicacionesService {
    private final JdbcTemplate db;private final ObjectMapper json;
    UbicacionesService(JdbcTemplate db,ObjectMapper json) {this.db=db;this.json=json;}
    static Map<String,Object> map(Object... v) {Map<String,Object> m=new LinkedHashMap<>();for(int i=0;i<v.length;i+=2)m.put(v[i].toString(),v[i+1]);return m;}
    private void permission(AuthClient.Identity a,boolean admin) {if(!a.has("ADMINISTRADOR")&&(admin||!a.has("BODEGUERO")))throw new UbicacionesError(403,"Sin permisos");}
    private void page(int page,int size) {if(page<0||size<1||size>100)throw new UbicacionesError(400,"Paginacion invalida");}
    private Map<String,Object> space(UUID id,boolean lock) {return db.queryForList("SELECT * FROM ubicaciones.space WHERE id=?"+(lock?" FOR UPDATE":""),id).stream().findFirst().orElseThrow(()->new UbicacionesError(404,"Ubicacion no encontrada"));}
    private long occupied(UUID id) {var s=space(id,false);return db.queryForObject("SELECT (SELECT count(*) FROM ubicaciones.placement WHERE space_id=? AND quantity>0)+(SELECT count(*) FROM retazos.piece WHERE lower(location)=lower(?) AND state IN ('DISPONIBLE','PREPARADO') AND NOT EXISTS(SELECT 1 FROM pedidos.fulfillment_item f WHERE f.piece_id=retazos.piece.id AND f.dispatched_quantity>0))",Long.class,id,s.get("code"));}
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Object spaces(String q,int page,int size) {page(page,size);if(q.length()>150)throw new UbicacionesError(400,"Filtro muy largo");String filter=q.toLowerCase(Locale.ROOT);var rows=db.queryForList("SELECT * FROM ubicaciones.space WHERE POSITION(? IN lower(code||' '||description))>0 ORDER BY code,id LIMIT ? OFFSET ?",filter,size,(long)page*size);for(var row:rows)row.put("occupiedItems",occupied((UUID)row.get("id")));return map("items",rows,"total",db.queryForObject("SELECT count(*) FROM ubicaciones.space WHERE POSITION(? IN lower(code||' '||description))>0",Long.class,filter),"page",page,"size",size);}
    @Transactional
    public Object save(UUID id,UbicacionesApi.Space r,AuthClient.Identity actor) {
        permission(actor,true);
        if(id==null) {id=UUID.randomUUID();db.update("INSERT INTO ubicaciones.space(id,code,description,active) VALUES (?,?,?,?)",id,r.code().trim(),r.description()==null?"":r.description().trim(),r.active());}
        else {
            var before=space(id,true);if(!before.get("code").equals(r.code().trim()))throw new UbicacionesError(409,"El codigo fisico es estable; crea otra ubicacion y traslada el material");
            if(!r.active()&&occupied(id)>0)throw new UbicacionesError(409,"La ubicacion contiene material; vaciala antes de desactivar");
            db.update("UPDATE ubicaciones.space SET description=?,active=? WHERE id=?",r.description()==null?"":r.description().trim(),r.active(),id);
        }
        audit(null,"UBICACION",actor,"Administracion del espacio",map("spaceId",id,"input",r));return space(id,false);
    }
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Object contents(UUID id) {var s=space(id,false);return map("space",s,"products",db.queryForList("SELECT p.product_id,i.code,i.name,p.quantity FROM ubicaciones.placement p JOIN inventario.product i ON i.id=p.product_id WHERE p.space_id=? AND p.quantity>0 ORDER BY i.name",id),"pieces",db.queryForList("SELECT p.id,p.product_id,i.code,i.name,p.length_m,p.width_cm,p.height_cm,p.state,EXISTS(SELECT 1 FROM inventario.stock_reservation r WHERE r.piece_id=p.id AND r.state='ACTIVA') AS reserved FROM retazos.piece p JOIN inventario.product i ON i.id=p.product_id WHERE lower(p.location)=lower(?) AND p.state IN ('DISPONIBLE','PREPARADO') AND NOT EXISTS(SELECT 1 FROM pedidos.fulfillment_item f WHERE f.piece_id=p.id AND f.dispatched_quantity>0) ORDER BY i.name,p.created_at,p.id",s.get("code")));}
    @Transactional(readOnly=true)
    public Object products(String q,int page,int size) {page(page,size);if(q.length()>150)throw new UbicacionesError(400,"Filtro muy largo");return map("items",db.queryForList("SELECT id,code,name,stock,pieces_managed FROM inventario.product WHERE POSITION(? IN lower(code||' '||name))>0 ORDER BY name,id LIMIT ? OFFSET ?",q.toLowerCase(Locale.ROOT),size,(long)page*size),"total",db.queryForObject("SELECT count(*) FROM inventario.product WHERE POSITION(? IN lower(code||' '||name))>0",Long.class,q.toLowerCase(Locale.ROOT)));}
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> product(UUID id) {
        var rows=db.queryForList("SELECT id,code,name,stock,pieces_managed FROM inventario.product WHERE id=?",id);if(rows.isEmpty())throw new UbicacionesError(404,"Producto no encontrado");var p=rows.getFirst();
        var placements=db.queryForList("SELECT s.id AS space_id,s.code,p.quantity FROM ubicaciones.placement p JOIN ubicaciones.space s ON s.id=p.space_id WHERE p.product_id=? AND p.quantity>0 ORDER BY s.code",id);
        BigDecimal assigned=db.queryForObject("SELECT COALESCE(SUM(quantity),0) FROM ubicaciones.placement WHERE product_id=?",BigDecimal.class,id);
        return map("product",p,"placements",placements,"unlocatedStock",Boolean.TRUE.equals(p.get("pieces_managed"))?null:((BigDecimal)p.get("stock")).subtract(assigned),"pieces",db.queryForList("SELECT id,length_m,width_cm,height_cm,location,state FROM retazos.piece WHERE product_id=? AND state IN ('DISPONIBLE','PREPARADO') AND NOT EXISTS(SELECT 1 FROM pedidos.fulfillment_item f WHERE f.piece_id=retazos.piece.id AND f.dispatched_quantity>0) ORDER BY created_at,id",id));
    }
    private String json(Object x) {try{return json.writeValueAsString(x);}catch(Exception e){throw new IllegalStateException(e);}}
    private void audit(UUID product,String action,AuthClient.Identity actor,String reason,Object detail) {db.update("INSERT INTO ubicaciones.event(product_id,action,actor_id,actor_name,reason,detail) VALUES (?,?,?,?,?,?::jsonb)",product,action,actor.id(),actor.fullName(),reason,json(detail));}
    @Transactional
    public Map<String,Object> move(UbicacionesApi.Move r,AuthClient.Identity actor) {
        permission(actor,false);String fingerprint=actor.id()+":"+json(r);
        db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0)) IS NULL",Boolean.class,r.requestId().toString());
        var prior=db.queryForList("SELECT * FROM ubicaciones.command WHERE request_id=?",r.requestId());
        if(!prior.isEmpty()) {if(!fingerprint.equals(prior.getFirst().get("fingerprint")))throw new UbicacionesError(409,"requestId ya usado con otros datos");try{return json.readValue(prior.getFirst().get("result").toString(),new com.fasterxml.jackson.core.type.TypeReference<Map<String,Object>>(){});}catch(Exception e){throw new IllegalStateException(e);}}
        var products=db.queryForList("SELECT * FROM inventario.product WHERE id=? FOR UPDATE",r.productId());if(products.isEmpty())throw new UbicacionesError(404,"Producto no encontrado");var p=products.getFirst();
        List<UUID> lockIds=new ArrayList<>(List.of(r.toSpaceId()));if(r.fromSpaceId()!=null)lockIds.add(r.fromSpaceId());lockIds.stream().distinct().sorted().forEach(x->space(x,true));
        var to=space(r.toSpaceId(),false);if(!Boolean.TRUE.equals(to.get("active")))throw new UbicacionesError(409,"Ubicacion de destino inactiva");
        if(r.toSpaceId().equals(r.fromSpaceId()))throw new UbicacionesError(400,"Origen y destino deben ser distintos");
        if(Boolean.TRUE.equals(p.get("pieces_managed"))) {
            if(r.quantity()!=null)throw new UbicacionesError(400,"Traslada piezas fisicas o todo el material de una ubicacion");
            List<UUID> pieces=r.pieceIds();
            if(pieces==null||pieces.isEmpty()) {
                String from=r.fromSpaceId()==null?"":space(r.fromSpaceId(),false).get("code").toString();
                pieces=db.query("SELECT id FROM retazos.piece WHERE product_id=? AND lower(location)=lower(?) AND state IN ('DISPONIBLE','PREPARADO') AND NOT EXISTS(SELECT 1 FROM pedidos.fulfillment_item f WHERE f.piece_id=retazos.piece.id AND f.dispatched_quantity>0) ORDER BY id",(rs,n)->rs.getObject(1,UUID.class),r.productId(),from);
            }
            if(pieces.isEmpty()||new HashSet<>(pieces).size()!=pieces.size())throw new UbicacionesError(409,"No hay piezas o la seleccion contiene duplicados");
            for(UUID piece:pieces) {
                var found=db.queryForList("SELECT * FROM retazos.piece WHERE id=? AND product_id=? AND state IN ('DISPONIBLE','PREPARADO') AND NOT EXISTS(SELECT 1 FROM pedidos.fulfillment_item f WHERE f.piece_id=retazos.piece.id AND f.dispatched_quantity>0)",piece,r.productId());if(found.isEmpty())throw new UbicacionesError(409,"Pieza no disponible fisicamente");
                if(r.fromSpaceId()!=null&&!found.getFirst().get("location").toString().equalsIgnoreCase(space(r.fromSpaceId(),false).get("code").toString()))throw new UbicacionesError(409,"La pieza no se encuentra en el origen indicado");
                db.update("UPDATE retazos.piece SET location=? WHERE id=?",to.get("code"),piece);
            }
        } else {
            if(r.pieceIds()!=null&&!r.pieceIds().isEmpty())throw new UbicacionesError(400,"Este producto se mueve por cantidad");
            BigDecimal available=r.fromSpaceId()==null?((BigDecimal)p.get("stock")).subtract(db.queryForObject("SELECT COALESCE(SUM(quantity),0) FROM ubicaciones.placement WHERE product_id=?",BigDecimal.class,r.productId())):db.queryForObject("SELECT COALESCE((SELECT quantity FROM ubicaciones.placement WHERE product_id=? AND space_id=?),0)",BigDecimal.class,r.productId(),r.fromSpaceId());
            BigDecimal quantity=r.quantity()==null?available:r.quantity();if(quantity.signum()<=0||quantity.compareTo(available)>0)throw new UbicacionesError(409,"Cantidad insuficiente en el origen");
            if(r.fromSpaceId()!=null)db.update("UPDATE ubicaciones.placement SET quantity=quantity-? WHERE product_id=? AND space_id=?",quantity,r.productId(),r.fromSpaceId());
            db.update("INSERT INTO ubicaciones.placement(product_id,space_id,quantity) VALUES (?,?,?) ON CONFLICT(product_id,space_id) DO UPDATE SET quantity=ubicaciones.placement.quantity+EXCLUDED.quantity",r.productId(),r.toSpaceId(),quantity);
        }
        audit(r.productId(),"TRASLADO",actor,r.reason().trim(),r);var result=product(r.productId());db.update("INSERT INTO ubicaciones.command(request_id,fingerprint,result) VALUES (?,?,?::jsonb)",r.requestId(),fingerprint,json(result));return result;
    }
    @Transactional(readOnly=true)
    public Object history(UUID product,int page,int size) {page(page,size);return map("items",db.queryForList("SELECT * FROM ubicaciones.event WHERE (?::uuid IS NULL OR product_id=?) ORDER BY created_at DESC,id LIMIT ? OFFSET ?",product,product,size,(long)page*size),"page",page,"size",size);}
}
