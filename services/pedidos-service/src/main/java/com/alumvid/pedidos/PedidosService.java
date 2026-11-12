package com.alumvid.pedidos;

import java.math.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;
import static com.alumvid.pedidos.AvailabilityPlanner.*;

@Service
class PedidosService {
    private final JdbcTemplate db;private final AvailabilityPlanner planner;private final ObjectMapper json;private final OrderFulfillment fulfillment;private final java.time.Clock clock;
    PedidosService(JdbcTemplate db,AvailabilityPlanner planner,ObjectMapper json,OrderFulfillment fulfillment,java.time.Clock clock) {this.db=db;this.planner=planner;this.json=json;this.fulfillment=fulfillment;this.clock=clock;}
    private static final Set<String> STATES=Set.of("BORRADOR","PENDIENTE_MATERIAL","RESERVADO","PARCIAL","LISTO","EN_REPARTO","ENTREGADO","RETRASADO","CANCELADO","VENCIDO");
    private void permission(AuthClient.Identity actor,String... roles) {if(Arrays.stream(roles).noneMatch(actor::has))throw new PedidosError(403,"Sin permisos para esta operacion");}
    private void page(int page,int size) {if(page<0||size<1||size>100)throw new PedidosError(400,"Pagina >=0 y tamano entre 1 y 100");}
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> products(String q,int page,int size) {
        page(page,size);if(q.length()>150)throw new PedidosError(400,"Filtro demasiado largo");String filter=q.trim().toLowerCase(Locale.ROOT);
        return map("items",db.queryForList("SELECT p.id,p.code,p.name,p.unit,p.stock,p.pieces_managed AS \"piecesManaged\",p.stock-COALESCE(r.reserved,0) AS \"availableStock\",COALESCE(r.reserved,0) AS \"reservedStock\",f.kind,f.full_length_m AS \"fullLengthM\",f.full_width_cm AS \"fullWidthCm\",f.full_height_cm AS \"fullHeightCm\" FROM inventario.product p LEFT JOIN retazos.material_format f ON f.product_id=p.id LEFT JOIN (SELECT product_id,SUM(quantity) AS reserved FROM inventario.stock_reservation WHERE state='ACTIVA' GROUP BY product_id) r ON r.product_id=p.id WHERE p.active AND POSITION(? IN LOWER(p.code||' '||p.name))>0 ORDER BY p.name,p.id LIMIT ? OFFSET ?",filter,size,(long)page*size),
            "total",db.queryForObject("SELECT count(*) FROM inventario.product WHERE active AND POSITION(? IN LOWER(code||' '||name))>0",Long.class,filter),"page",page,"size",size);
    }
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> availability(List<PedidosApi.Line> lines) {var plan=planner.plan(lines);return map("available",plan.available(),"lines",plan.lines(),"notice","Consulta informativa: no crea pedidos ni reservas. Se verifica de nuevo al confirmar.");}
    private String serialize(Object x) {try{return json.writeValueAsString(x);}catch(Exception e){throw new IllegalStateException(e);}}
    private Map<String,Object> parse(String x) {try{return json.readValue(x,new TypeReference<Map<String,Object>>(){});}catch(Exception e){throw new IllegalStateException(e);}}
    private String key(String action,Object input,AuthClient.Identity actor) {try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest((action+":"+actor.id()+":"+serialize(input)).getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
    private Map<String,Object> previous(UUID request,String key) {
        // Serializa reintentos incluso si el primer intento aun no ha insertado su resultado.
        db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0)) IS NULL",Boolean.class,request.toString());
        var rows=db.queryForList("SELECT * FROM pedidos.command WHERE request_id=?",request);
        if(rows.isEmpty())return null;if(!key.equals(rows.getFirst().get("fingerprint")))throw new PedidosError(409,"requestId ya utilizado con otros datos");return parse(rows.getFirst().get("result").toString());
    }
    private Map<String,Object> finish(UUID request,String key,UUID id) {var result=get(id);db.update("INSERT INTO pedidos.command(request_id,fingerprint,result) VALUES (?,?,?::jsonb)",request,key,serialize(result));return result;}
    private void event(UUID id,String action,String reason,AuthClient.Identity actor,Object detail) {db.update("INSERT INTO pedidos.order_event(id,order_id,action,reason,actor_id,actor_name,detail) VALUES (?,?,?,?,?,?,?::jsonb)",UUID.randomUUID(),id,action,reason.trim(),actor.id(),actor.fullName(),serialize(detail));}
    @Transactional
    public Map<String,Object> create(PedidosApi.Create r,AuthClient.Identity actor) {
        permission(actor,"ADMINISTRADOR","VENDEDOR");String key=key("CREATE",r,actor);var old=previous(r.requestId(),key);if(old!=null)return old;
        if(r.deliveryMode()==PedidosApi.Delivery.ENTREGA&&text(r.deliveryAddress()).isEmpty())throw new PedidosError(400,"Indica la ubicacion de entrega");
        if(!Boolean.TRUE.equals(r.externallyConfirmed()))throw new PedidosError(400,"Solo se registran pedidos confirmados y pagados fuera del sistema");
        UUID clientId=r.clientId();String clientName;
        if(clientId==null) {
            if(text(r.clientName()).isEmpty())throw new PedidosError(400,"Selecciona un cliente del catalogo");
            clientId=UUID.randomUUID();clientName=r.clientName().trim();db.update("INSERT INTO pedidos.client(id,name) VALUES (?,?)",clientId,clientName);
        } else {
            var clients=db.queryForList("SELECT * FROM pedidos.client WHERE id=? AND active",clientId);
            if(clients.isEmpty())throw new PedidosError(409,"Cliente inexistente o desactivado");clientName=clients.getFirst().get("name").toString();
        }
        planner.plan(r.lines()); // valida medidas sin prometer ni reservar disponibilidad.
        BigDecimal total=r.lines().stream().map(x->x.quantity().multiply(x.unitPrice()).setScale(2,RoundingMode.HALF_UP)).reduce(BigDecimal.ZERO,BigDecimal::add);
        UUID id=UUID.randomUUID();db.update("INSERT INTO pedidos.sale_order(id,client_name,delivery_mode,delivery_address,receiver_name,notes,total,created_by) VALUES (?,?,?,?,?,?,?,?)",id,clientName,r.deliveryMode().name(),text(r.deliveryAddress()),text(r.receiverName()),text(r.notes()),total,actor.id());
        int i=0;for(var line:r.lines()) {var p=planner.product(line.productId());db.update("INSERT INTO pedidos.order_line(id,order_id,position,product_id,product_code,product_name,quantity,length_m,width_cm,height_cm,waste_extent,unit_price) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",UUID.randomUUID(),id,i++,line.productId(),p.get("code"),p.get("name"),line.quantity(),line.lengthM(),line.widthCm(),line.heightCm(),line.wasteExtent()==null?BigDecimal.ZERO:line.wasteExtent(),line.unitPrice());}
        db.update("UPDATE pedidos.sale_order SET client_id=?,external_invoice_reference=?,externally_confirmed=TRUE,confirmed_at=?,expires_at=? WHERE id=?",clientId,text(r.externalInvoiceReference()),java.sql.Timestamp.from(clock.instant()),java.sql.Timestamp.from(clock.instant().plus(java.time.Duration.ofHours(72))),id);
        lockProducts(lines(id));reserve(id,lines(id),actor,"Pedido confirmado y pagado externamente");
        event(id,"CREADO","Pedido confirmado externamente; no se procesan cobros",actor,map("total",total,"currency","USD","clientId",clientId));return finish(r.requestId(),key,id);
    }
    static String text(String value) {return value==null?"":value.trim();}
    private List<Map<String,Object>> lines(UUID id) {return db.queryForList("SELECT * FROM pedidos.order_line WHERE order_id=? ORDER BY position",id);}
    private List<PedidosApi.Line> inputs(List<Map<String,Object>> rows) {return rows.stream().map(x->new PedidosApi.Line(uuid(x.get("product_id")),decimal(x.get("quantity")),(BigDecimal)x.get("length_m"),(BigDecimal)x.get("width_cm"),(BigDecimal)x.get("height_cm"),decimal(x.get("waste_extent")),decimal(x.get("unit_price")))).toList();}
    private Map<String,Object> order(UUID id,boolean lock) {return db.queryForList("SELECT * FROM pedidos.sale_order WHERE id=?"+(lock?" FOR UPDATE":""),id).stream().findFirst().orElseThrow(()->new PedidosError(404,"Pedido no encontrado"));}
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> get(UUID id) {return map("order",order(id,false),"lines",lines(id),"allocations",db.queryForList("SELECT a.*,p.location FROM pedidos.allocation a LEFT JOIN retazos.piece p ON p.id=a.piece_id WHERE a.order_id=? ORDER BY a.created_at,a.id",id),"reservations",db.queryForList("SELECT * FROM inventario.stock_reservation WHERE order_id=? ORDER BY created_at,id",id),"fulfillments",db.queryForList("SELECT f.*,p.length_m,p.width_cm,p.height_cm,p.location AS current_location FROM pedidos.fulfillment_item f LEFT JOIN retazos.piece p ON p.id=f.piece_id WHERE f.order_id=? ORDER BY f.created_at,f.id",id),"events",events(id));}
    private List<Map<String,Object>> events(UUID id) {var rows=db.queryForList("SELECT id,action,reason,actor_name,detail,created_at FROM pedidos.order_event WHERE order_id=? ORDER BY created_at,id",id);for(var row:rows)row.put("detail",parse(row.get("detail").toString()));return rows;}
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> list(String state,String q,int page,int size) {page(page,size);if(!state.isEmpty()&&!STATES.contains(state))throw new PedidosError(400,"Estado invalido");if(q.length()>150)throw new PedidosError(400,"Filtro demasiado largo");String filter=q.trim().toLowerCase(Locale.ROOT);String where=" WHERE (?='' OR state=?) AND POSITION(? IN LOWER(client_name||' '||number::text))>0";return map("items",db.queryForList("SELECT * FROM pedidos.sale_order"+where+" ORDER BY created_at DESC,id LIMIT ? OFFSET ?",state,state,filter,size,(long)page*size),"total",db.queryForObject("SELECT count(*) FROM pedidos.sale_order"+where,Long.class,state,state,filter),"page",page,"size",size);}
    private void state(UUID id,String value) {db.update("UPDATE pedidos.sale_order SET state=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",value,id);}
    private void release(UUID id,String value) {db.update("UPDATE inventario.stock_reservation SET state=?,updated_at=CURRENT_TIMESTAMP WHERE order_id=? AND state='ACTIVA'",value,id);db.update("UPDATE pedidos.allocation SET state=? WHERE order_id=? AND state='ACTIVA'",value,id);}
    private static final AuthClient.Identity SYSTEM=new AuthClient.Identity(new UUID(0,0),"SYSTEM","Vencimiento automatico",Set.of("ADMINISTRADOR"),false,true,false);
    private void lockProducts(List<Map<String,Object>> rows) {rows.stream().map(x->uuid(x.get("product_id"))).distinct().sorted().forEach(p->db.queryForList("SELECT id FROM inventario.product WHERE id=? FOR UPDATE",p));}
    private boolean terminal(String value) {return Set.of("CANCELADO","VENCIDO","ENTREGADO").contains(value);}
    private java.time.Instant instant(Object value) {return value instanceof java.time.OffsetDateTime t?t.toInstant():((java.util.Date)value).toInstant();}
    private boolean overdue(Map<String,Object> order) {return order.get("expires_at")!=null&&!instant(order.get("expires_at")).isAfter(clock.instant());}
    private void renew(UUID id) {db.update("UPDATE pedidos.sale_order SET expires_at=? WHERE id=?",java.sql.Timestamp.from(clock.instant().plus(java.time.Duration.ofHours(72))),id);}
    @Transactional
    public void expire(UUID id) {
        var order=order(id,true);if(terminal(order.get("state").toString())||!overdue(order))return;
        lockProducts(lines(id));var action=new PedidosApi.Action(UUID.randomUUID(),"Reserva vencida al alcanzar 72 horas");
        close(id,"VENCIDO",action,SYSTEM);event(id,"VENCIMIENTO",action.reason(),SYSTEM,map("expiresAt",order.get("expires_at"),"transit","Lo no recibido fisicamente permanece pendiente de retorno"));
    }
    private void close(UUID id,String state,PedidosApi.Action action,AuthClient.Identity actor) {
        db.queryForObject("SELECT pedidos.cancel_order_shipments(?,?) IS NULL",Boolean.class,id,action.reason());
        fulfillment.returnToStock(id,action,actor,false);release(id,"LIBERADA");
        db.update("UPDATE pedidos.order_line SET state=CASE WHEN delivered_quantity=quantity THEN 'ENTREGADO' ELSE ? END,reserved_quantity=0 WHERE order_id=?",state,id);state(id,state);
    }
    @Transactional
    public Map<String,Object> action(UUID id,String action,PedidosApi.Action r,AuthClient.Identity actor) {
        switch(action) {
            case "confirm","retry","cancel"->permission(actor,"ADMINISTRADOR","VENDEDOR");
            case "prepare","dispatch","deliver","receive-return"->permission(actor,"ADMINISTRADOR","BODEGUERO");
            case "delay","resume"->permission(actor,"ADMINISTRADOR","VENDEDOR","BODEGUERO");
            default->throw new PedidosError(400,"Accion invalida");
        }
        String key=key(action+":"+id,r,actor);var old=previous(r.requestId(),key);if(old!=null)return old;
        var order=order(id,true);String before=order.get("state").toString();var rows=lines(id);lockProducts(rows);
        if(Set.of("deliver","receive-return").contains(action)&&db.queryForObject("SELECT count(*) FROM pedidos.commercial_shipment WHERE order_id=? AND state IN ('EN_REPARTO','RETORNO_PENDIENTE')",Long.class,id)>0)
            throw new PedidosError(409,"Gestiona la entrega desde logística o recibe cada despacho vinculado en bodega");
        if(!terminal(before)&&overdue(order))throw new PedidosError(409,"La reserva vencio; no puede ampliarse ni entregarse. El proceso automatico devolvera el pendiente a bodega.");
        switch(action) {
            case "confirm"->{
                if(before.equals("BORRADOR")) {reserve(id,rows,actor,r.reason());db.update("UPDATE pedidos.sale_order SET externally_confirmed=TRUE,confirmed_at=? WHERE id=?",java.sql.Timestamp.from(clock.instant()),id);renew(id);}
                else if(!Boolean.TRUE.equals(order.get("externally_confirmed"))||terminal(before))throw new PedidosError(409,"Pedido ya cerrado");
            }
            case "retry"->{require(before,"PENDIENTE_MATERIAL");reserve(id,rows,actor,r.reason());}
            case "prepare"->{require(before,"RESERVADO","PARCIAL","LISTO","EN_REPARTO");fulfillment.prepare(id,r,actor);state(id,fulfillment.refresh(id));}
            case "cancel"->{require(before,"BORRADOR","PENDIENTE_MATERIAL","RESERVADO","PARCIAL","RETRASADO","LISTO","EN_REPARTO");close(id,"CANCELADO",r,actor);}
            case "delay"->{require(before,"PENDIENTE_MATERIAL","RESERVADO","PARCIAL","LISTO","EN_REPARTO");db.update("UPDATE pedidos.sale_order SET resume_state=? WHERE id=?",before,id);state(id,"RETRASADO");renew(id);}
            case "resume"->{require(before,"RETRASADO");state(id,order.get("resume_state").toString());db.update("UPDATE pedidos.sale_order SET resume_state=NULL WHERE id=?",id);}
            case "dispatch"->{require(before,"PARCIAL","LISTO","EN_REPARTO");if(!"ENTREGA".equals(order.get("delivery_mode")))throw new PedidosError(409,"Pedido para retiro en local");fulfillment.move(id,r,"dispatch",true);state(id,fulfillment.refresh(id));}
            case "deliver"->{require(before,"PARCIAL","LISTO","EN_REPARTO");fulfillment.move(id,r,"deliver","ENTREGA".equals(order.get("delivery_mode")));String next=fulfillment.refresh(id);state(id,next);if(!next.equals("ENTREGADO"))renew(id);}
            case "receive-return"->{require(before,"CANCELADO","VENCIDO");fulfillment.returnToStock(id,r,actor,true);}
        }
        event(id,action.toUpperCase(Locale.ROOT),r.reason(),actor,map("before",before,"after",order(id,false).get("state"),"lines",r.lines(),"receiverName",text(r.receiverName()),"expiresAt",order(id,false).get("expires_at")));
        return finish(r.requestId(),key,id);
    }
    private void require(String current,String... allowed) {if(Arrays.stream(allowed).noneMatch(current::equals))throw new PedidosError(409,"Accion no permitida desde "+current);}
    private void reserve(UUID id,List<Map<String,Object>> rows,AuthClient.Identity actor,String reason) {
        release(id,"LIBERADA");var plan=planner.plan(inputs(rows));
        Set<UUID> reservedPieces=new HashSet<>();
        for(var a:plan.allocations()) {
            UUID line=uuid(rows.get(a.position()).get("id"));
            db.update("INSERT INTO pedidos.allocation(id,order_id,line_id,product_id,piece_id,used_extent,waste_extent,quantity) VALUES (?,?,?,?,?,?,?,?)",UUID.randomUUID(),id,line,a.productId(),a.pieceId(),a.extent(),a.waste(),a.quantity());
            if(a.pieceId()==null)reserveStock(id,a.productId(),null,a.quantity());
            else if(reservedPieces.add(a.pieceId())) {
                var p=planner.product(a.productId());var piece=db.queryForMap("SELECT * FROM retazos.piece WHERE id=?",a.pieceId());
                boolean aluminum="ALUMINIO".equals(p.get("kind"));BigDecimal measure=aluminum?decimal(piece.get("length_m")):decimal(piece.get("width_cm")).multiply(decimal(piece.get("height_cm")));
                BigDecimal reference=aluminum?decimal(p.get("full_length_m")):decimal(p.get("full_width_cm")).multiply(decimal(p.get("full_height_cm")));
                // La unicidad de piece_id protege la pieza entera; truncar evita sumar redondeos por encima del saldo.
                BigDecimal quantity=measure.divide(reference,12,RoundingMode.DOWN);
                if(quantity.signum()==0)throw new PedidosError(409,"Pieza demasiado pequena para reservar con la precision actual");
                reserveStock(id,a.productId(),a.pieceId(),quantity);
            }
        }
        for(var line:plan.lines())db.update("UPDATE pedidos.order_line SET state=?,reserved_quantity=? WHERE id=?",line.get("state"),line.get("availableQuantity"),rows.get((Integer)line.get("position")).get("id"));
        state(id,plan.available()?"RESERVADO":"PENDIENTE_MATERIAL");
        event(id,"DISPONIBILIDAD",reason,actor,map("available",plan.available(),"lines",plan.lines()));
    }
    private void reserveStock(UUID order,UUID product,UUID piece,BigDecimal quantity) {db.update("INSERT INTO inventario.stock_reservation(id,order_id,product_id,piece_id,quantity) VALUES (?,?,?,?,?)",UUID.randomUUID(),order,product,piece,quantity);}
}
