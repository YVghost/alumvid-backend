package com.alumvid.retazos;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import static com.alumvid.retazos.RetazosRepository.map;

@Service
class RetazosService {
    private final RetazosRepository repository;
    private final InventoryLedger ledger;
    private final ObjectMapper json;
    RetazosService(RetazosRepository repository,InventoryLedger ledger,ObjectMapper json) { this.repository=repository;this.ledger=ledger;this.json=json; }
    private void admin(AuthClient.Identity actor) { if(!actor.has("ADMINISTRADOR"))throw new RetazosError(403,"Se requiere un administrador"); }
    private void writer(AuthClient.Identity actor) { if(!actor.has("ADMINISTRADOR")&&!actor.has("BODEGUERO"))throw new RetazosError(403,"Se requiere administrador o bodeguero"); }
    private BigDecimal stock(Map<String,Object> p) { return (BigDecimal)p.get("stock"); }
    private void unreserved(UUID piece) { if(repository.db().queryForObject("SELECT count(*) FROM inventario.stock_reservation WHERE piece_id=? AND state='ACTIVA'",Long.class,piece)>0)throw new RetazosError(409,"Pieza reservada por un pedido; preparala desde Pedidos o libera la reserva"); }
    private void active(Map<String,Object> p) { if(!Boolean.TRUE.equals(p.get("active")))throw new RetazosError(409,"El producto está inactivo"); }
    @Transactional
    public Map<String,Object> configure(UUID id,RetazosApi.FormatInput r,AuthClient.Identity actor) {
        admin(actor);var product=repository.product(id,true);active(product);
        if(repository.db().queryForObject("SELECT count(*) FROM inventario.stock_reservation WHERE product_id=? AND state='ACTIVA'",Long.class,id)>0 && repository.optionalFormat(id).isEmpty())throw new RetazosError(409,"Libera las reservas antes de activar el desglose por piezas");
        if(!"UNIDAD".equals(product.get("unit")))throw new RetazosError(409,"El producto debe usar UNIDAD como perfil o plancha completos");
        if(r.kind()==RetazosApi.Kind.ALUMINIO) {
            MaterialMath.positive(r.fullLengthM(),"Longitud del perfil completo");
            if(r.fullWidthCm()!=null||r.fullHeightCm()!=null)throw new RetazosError(400,"Aluminio utiliza solo longitud en metros");
        } else {
            MaterialMath.positive(r.fullWidthCm(),"Ancho completo");MaterialMath.positive(r.fullHeightCm(),"Alto completo");
            if(r.fullLengthM()!=null)throw new RetazosError(400,"Vidrio utiliza ancho y alto en centímetros");
        }
        var old=repository.optionalFormat(id);
        if(old.isPresent()) {
            var f=old.get();
            if(!f.kind().equals(r.kind().name())||!equal(f.fullLengthM(),r.fullLengthM())||!equal(f.fullWidthCm(),r.fullWidthCm())||!equal(f.fullHeightCm(),r.fullHeightCm()))
                throw new RetazosError(409,"La referencia completa ya está definida; cambiarla alteraría las equivalencias históricas");
            return summary(id);
        }
        BigDecimal reference=r.kind()==RetazosApi.Kind.ALUMINIO?r.fullLengthM():r.fullWidthCm().multiply(r.fullHeightCm());
        repository.db().update("INSERT INTO retazos.material_format(product_id,kind,full_length_m,full_width_cm,full_height_cm,unallocated_measure,created_by) VALUES (?,?,?,?,?,?,?)",
            id,r.kind().name(),r.fullLengthM(),r.fullWidthCm(),r.fullHeightCm(),reference.multiply(stock(product)),actor.id());
        repository.db().update("UPDATE inventario.product SET pieces_managed=TRUE,updated_at=CURRENT_TIMESTAMP WHERE id=?",id);
        repository.db().update("INSERT INTO inventario.catalog_event(id,product_id,actor_id,actor_name,action,detail) VALUES (?,?,?,?,?,?)",
            UUID.randomUUID(),id,actor.id(),actor.fullName(),"PIECES_ENABLED","Unidad completa: "+r+". Stock existente pendiente de desglose.");
        return summary(id);
    }
    private boolean equal(BigDecimal a,BigDecimal b) { return a==null?b==null:b!=null&&a.compareTo(b)==0; }
    private void consistent(RetazosRepository.Format f,BigDecimal stock) {
        if(repository.totalStock(f).compareTo(stock)!=0)throw new RetazosError(409,"El stock general y el desglose no coinciden; revisa los movimientos antes de operar");
    }
    private String fingerprint(String action,Object request,AuthClient.Identity actor) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest((action+":"+actor.id()+":"+json.writeValueAsString(request)).getBytes(StandardCharsets.UTF_8))); }
        catch(Exception e) { throw new IllegalStateException(e); }
    }
    private Map<String,Object> previous(UUID product,UUID request,String fingerprint) {
        var rows=repository.db().queryForList("SELECT fingerprint,result::text AS result FROM retazos.operation WHERE product_id=? AND request_id=?",product,request);
        if(rows.isEmpty())return null;
        if(!fingerprint.equals(rows.get(0).get("fingerprint")))throw new RetazosError(409,"El identificador de operación ya se utilizó con otros datos o usuario");
        try { return json.readValue((String)rows.get(0).get("result"),new TypeReference<Map<String,Object>>(){}); }
        catch(Exception e) { throw new IllegalStateException(e); }
    }
    private Map<String,Object> finish(UUID product,UUID request,String action,String fingerprint,String reason,AuthClient.Identity actor,BigDecimal before,List<UUID> pieces,Map<String,Object> detail,boolean adjustment) {
        var f=repository.format(product);var after=repository.totalStock(f);
        UUID movement=ledger.apply(product,request,before,after,reason.trim(),actor,adjustment);
        UUID id=UUID.randomUUID();
        var result=map("id",id,"requestId",request,"action",action,"productId",product,"stockBefore",before,"stockAfter",after,
            "inventoryDelta",after.subtract(before),"inventoryMovementId",movement,"pieceIds",pieces,"detail",detail);
        try {
            repository.db().update("INSERT INTO retazos.operation(id,product_id,request_id,fingerprint,action,actor_id,actor_name,reason,result) VALUES (?,?,?,?,?,?,?,?,?::jsonb)",
                id,product,request,fingerprint,action,actor.id(),actor.fullName(),reason.trim(),json.writeValueAsString(result));
        } catch(com.fasterxml.jackson.core.JsonProcessingException e) { throw new IllegalStateException(e); }
        return result;
    }
    @Transactional
    public Map<String,Object> register(UUID productId,RetazosApi.RegisterInput r,AuthClient.Identity actor) {
        writer(actor);if(r.mode()==RetazosApi.EntryMode.EXISTENTE)admin(actor);
        var product=repository.product(productId,true);
        String key=fingerprint("REGISTRO",r,actor);var previous=previous(productId,r.requestId(),key);if(previous!=null)return previous;
        active(product);var f=repository.format(productId);consistent(f,stock(product));
        BigDecimal measure;
        if(f.kind().equals("ALUMINIO")) {
            MaterialMath.positive(r.lengthM(),"Longitud");
            if(r.widthCm()!=null||r.heightCm()!=null||r.lengthM().compareTo(f.fullLengthM())>0)throw new RetazosError(400,"El retazo de aluminio debe tener solo longitud y no superar el perfil completo");
            measure=r.lengthM();
        } else {
            MaterialMath.positive(r.widthCm(),"Ancho");MaterialMath.positive(r.heightCm(),"Alto");
            if(r.lengthM()!=null||r.widthCm().compareTo(f.fullWidthCm())>0||r.heightCm().compareTo(f.fullHeightCm())!=0)
                throw new RetazosError(400,"El vidrio conserva el alto de la plancha completa; solo cambia su ancho");
            measure=r.widthCm().multiply(r.heightCm());
        }
        BigDecimal batch=measure.multiply(BigDecimal.valueOf(r.quantity()));
        if(r.mode()==RetazosApi.EntryMode.EXISTENTE) {
            if(batch.compareTo(f.unallocatedMeasure())>0)throw new RetazosError(409,"Las piezas superan el stock pendiente de desglose; no se sumaron existencias");
            repository.db().update("UPDATE retazos.material_format SET unallocated_measure=unallocated_measure-? WHERE product_id=?",batch,productId);
        }
        List<UUID> ids=new ArrayList<>();
        for(int i=0;i<r.quantity();i++)ids.add(repository.insert(productId,null,r.lengthM(),r.widthCm(),r.heightCm(),r.location()==null?"":r.location().trim()));
        return finish(productId,r.requestId(),"REGISTRO_"+r.mode(),key,r.reason(),actor,stock(product),ids,map("quantity",r.quantity(),"mode",r.mode()),false);
    }
    @Transactional
    public Map<String,Object> cut(UUID productId,UUID pieceId,RetazosApi.CutInput r,AuthClient.Identity actor) {
        writer(actor);var product=repository.product(productId,true);String key=fingerprint("CORTE:"+pieceId,r,actor);
        var previous=previous(productId,r.requestId(),key);if(previous!=null)return previous;
        active(product);var f=repository.format(productId);consistent(f,stock(product));var p=repository.piece(productId,pieceId);unreserved(pieceId);
        if(!p.state().equals("DISPONIBLE"))throw new RetazosError(409,"La pieza ya fue utilizada o descartada");
        boolean aluminum=f.kind().equals("ALUMINIO");
        BigDecimal used=aluminum?r.usedLengthM():r.usedWidthCm();MaterialMath.positive(used,aluminum?"Longitud utilizada":"Ancho utilizado");
        if((aluminum&&(r.usedWidthCm()!=null||r.wasteWidthCm()!=null))||(!aluminum&&(r.usedLengthM()!=null||r.wasteLengthM()!=null)))throw new RetazosError(400,"Las medidas no corresponden al material");
        BigDecimal waste=MaterialMath.zero(aluminum?r.wasteLengthM():r.wasteWidthCm());
        if(waste.signum()<0)throw new RetazosError(400,"La merma no puede ser negativa");
        BigDecimal remaining=(aluminum?p.lengthM():p.widthCm()).subtract(used).subtract(waste);
        if(remaining.signum()<0)throw new RetazosError(409,"El corte y la merma superan la pieza disponible");
        if(p.full(f) && hasSuitableRemnant(f,used.add(waste),pieceId))throw new RetazosError(409,"Hay un retazo que permite este corte; utilízalo antes de abrir material completo");
        repository.db().update("UPDATE retazos.piece SET state=? WHERE id=?",remaining.signum()>0?"TRANSFORMADO":"CONSUMIDO",pieceId);
        List<UUID> ids=new ArrayList<>();
        if(remaining.signum()>0)ids.add(repository.insert(productId,pieceId,aluminum?remaining:null,aluminum?null:remaining,p.heightCm(),p.location()));
        BigDecimal usedMeasure=aluminum?used:used.multiply(p.heightCm());
        BigDecimal wasteMeasure=aluminum?waste:waste.multiply(p.heightCm());
        return finish(productId,r.requestId(),"CORTE",key,r.reason(),actor,stock(product),ids,
            map("sourcePieceId",pieceId,"usedMeasure",usedMeasure,"wasteMeasure",wasteMeasure,"measureUnit",aluminum?"m":"cm2","remainingExtent",remaining),false);
    }
    private boolean hasSuitableRemnant(RetazosRepository.Format f,BigDecimal extent,UUID excluded) {
        String column=f.kind().equals("ALUMINIO")?"length_m":"width_cm";
        BigDecimal full=f.kind().equals("ALUMINIO")?f.fullLengthM():f.fullWidthCm();
        return repository.db().queryForObject("SELECT count(*) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE' AND id<>? AND NOT EXISTS(SELECT 1 FROM inventario.stock_reservation r WHERE r.piece_id=retazos.piece.id AND r.state='ACTIVA') AND "+column+">=? AND "+column+"<?",Long.class,f.productId(),excluded,extent,full)>0;
    }
    @Transactional
    public Map<String,Object> discard(UUID productId,UUID pieceId,RetazosApi.ReasonInput r,AuthClient.Identity actor) {
        writer(actor);var product=repository.product(productId,true);String key=fingerprint("DESCARTE:"+pieceId,r,actor);
        var previous=previous(productId,r.requestId(),key);if(previous!=null)return previous;
        active(product);var f=repository.format(productId);consistent(f,stock(product));var p=repository.piece(productId,pieceId);unreserved(pieceId);
        if(!p.state().equals("DISPONIBLE"))throw new RetazosError(409,"La pieza ya no está disponible");
        repository.db().update("UPDATE retazos.piece SET state='DESCARTADO' WHERE id=?",pieceId);
        return finish(productId,r.requestId(),"DESCARTE",key,r.reason(),actor,stock(product),List.of(),map("sourcePieceId",pieceId),false);
    }
    @Transactional
    public Map<String,Object> reconcile(UUID productId,RetazosApi.ReconcileInput r,AuthClient.Identity actor) {
        admin(actor);var product=repository.product(productId,true);String key=fingerprint("RECONCILIACION",r,actor);
        var previous=previous(productId,r.requestId(),key);if(previous!=null)return previous;
        active(product);var f=repository.format(productId);consistent(f,stock(product));
        repository.db().update("UPDATE retazos.material_format SET unallocated_measure=? WHERE product_id=?",r.unallocatedUnits().multiply(f.referenceMeasure()),productId);
        return finish(productId,r.requestId(),"RECONCILIACION",key,r.reason(),actor,stock(product),List.of(),map("unallocatedUnits",r.unallocatedUnits()),true);
    }
    @Transactional(readOnly=true,isolation=org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
    public Map<String,Object> summary(UUID productId) {
        var p=repository.product(productId,false);var f=repository.format(productId);
        var totals=repository.db().queryForMap("SELECT count(*) AS pieces,COALESCE(SUM(COALESCE(length_m,width_cm*height_cm)),0) AS measure,COALESCE(SUM(CASE WHEN COALESCE(length_m,width_cm*height_cm)=? THEN 1 ELSE 0 END),0) AS full_count FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE'",f.referenceMeasure(),productId);
        long count=((Number)totals.get("pieces")).longValue(),full=((Number)totals.get("full_count")).longValue();
        var groups=repository.db().queryForList("SELECT length_m AS \"lengthM\",width_cm AS \"widthCm\",height_cm AS \"heightCm\",location,count(*) AS quantity,COALESCE(length_m,width_cm*height_cm) AS measure FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE' GROUP BY length_m,width_cm,height_cm,location ORDER BY measure,location",productId);
        for(var group:groups) {
            var m=(BigDecimal)group.get("measure");group.put("equivalentPerPiece",MaterialMath.equivalent(m,f.referenceMeasure()));
            group.put("percentagePerPiece",MaterialMath.percentage(m,f.referenceMeasure()));
            group.put("equivalentTotal",MaterialMath.equivalent(m.multiply(BigDecimal.valueOf(((Number)group.get("quantity")).longValue())),f.referenceMeasure()));
            group.put("areaCm2",f.kind().equals("VIDRIO")?m:null);group.put("fullPiece",m.compareTo(f.referenceMeasure())==0);
        }
        BigDecimal unallocated=MaterialMath.equivalent(f.unallocatedMeasure(),f.referenceMeasure());
        return map("product",p,"kind",f.kind(),"fullLengthM",f.fullLengthM(),"fullWidthCm",f.fullWidthCm(),"fullHeightCm",f.fullHeightCm(),
            "referenceMeasure",f.referenceMeasure(),"availablePieces",count,"fullPieces",full,"remnantPieces",count-full,
            "allocatedUnits",MaterialMath.equivalent((BigDecimal)totals.get("measure"),f.referenceMeasure()),"unallocatedUnits",unallocated,
            "calculatedStock",repository.totalStock(f),"breakdown",groups);
    }
}
