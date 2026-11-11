package com.alumvid.retazos;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
class RetazosRepository {
    record Format(UUID productId,String kind,BigDecimal fullLengthM,BigDecimal fullWidthCm,BigDecimal fullHeightCm,BigDecimal unallocatedMeasure) {
        BigDecimal referenceMeasure() { return kind.equals("ALUMINIO")?fullLengthM:fullWidthCm.multiply(fullHeightCm); }
    }
    record Piece(UUID id,UUID productId,UUID parentId,BigDecimal lengthM,BigDecimal widthCm,BigDecimal heightCm,String state,String location,OffsetDateTime createdAt) {
        BigDecimal measure() { return lengthM!=null?lengthM:widthCm.multiply(heightCm); }
        boolean full(Format f) { return measure().compareTo(f.referenceMeasure())==0; }
        Map<String,Object> view(Format f) {
            return map("id",id,"productId",productId,"parentId",parentId,"lengthM",lengthM,"widthCm",widthCm,"heightCm",heightCm,
                "areaCm2",widthCm==null?null:measure(),"equivalentUnits",MaterialMath.equivalent(measure(),f.referenceMeasure()),
                "percentage",MaterialMath.percentage(measure(),f.referenceMeasure()),"fullPiece",full(f),"state",state,"location",location,"createdAt",createdAt);
        }
    }
    private final JdbcTemplate db;
    RetazosRepository(JdbcTemplate db) { this.db=db; }
    JdbcTemplate db() { return db; }
    static Map<String,Object> map(Object... values) {
        Map<String,Object> result=new LinkedHashMap<>();
        for(int i=0;i<values.length;i+=2)result.put((String)values[i],values[i+1]);
        return result;
    }
    Map<String,Object> product(UUID id,boolean lock) {
        return db.queryForList("SELECT id,code,name,unit,stock,active,pieces_managed FROM inventario.product WHERE id=?"+(lock?" FOR UPDATE":""),id)
            .stream().findFirst().orElseThrow(()->new RetazosError(404,"Producto no encontrado"));
    }
    Format format(UUID id) {
        return optionalFormat(id).orElseThrow(()->new RetazosError(404,"Configura primero las medidas de la unidad completa"));
    }
    Optional<Format> optionalFormat(UUID id) {
        return db.query("SELECT * FROM retazos.material_format WHERE product_id=?",(r,n)->new Format(id,r.getString("kind"),r.getBigDecimal("full_length_m"),r.getBigDecimal("full_width_cm"),r.getBigDecimal("full_height_cm"),r.getBigDecimal("unallocated_measure")),id).stream().findFirst();
    }
    List<Piece> pieces(UUID id,String state,int size,long offset) {
        return db.query("SELECT * FROM retazos.piece WHERE product_id=? AND (?='' OR state=?) ORDER BY created_at,id LIMIT ? OFFSET ?",
            (r,n)->new Piece(r.getObject("id",UUID.class),r.getObject("product_id",UUID.class),r.getObject("parent_id",UUID.class),r.getBigDecimal("length_m"),r.getBigDecimal("width_cm"),r.getBigDecimal("height_cm"),r.getString("state"),r.getString("location"),r.getObject("created_at",OffsetDateTime.class)),id,state,state,size,offset);
    }
    Piece piece(UUID productId,UUID pieceId) {
        return db.query("SELECT * FROM retazos.piece WHERE product_id=? AND id=?",
            (r,n)->new Piece(pieceId,productId,r.getObject("parent_id",UUID.class),r.getBigDecimal("length_m"),r.getBigDecimal("width_cm"),r.getBigDecimal("height_cm"),r.getString("state"),r.getString("location"),r.getObject("created_at",OffsetDateTime.class)),productId,pieceId)
            .stream().findFirst().orElseThrow(()->new RetazosError(404,"Pieza no encontrada en este producto"));
    }
    BigDecimal allocatedMeasure(UUID id) {
        return db.queryForObject("SELECT COALESCE(SUM(COALESCE(length_m,width_cm*height_cm)),0) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE'",BigDecimal.class,id);
    }
    BigDecimal totalStock(Format f) { return MaterialMath.equivalent(f.unallocatedMeasure().add(allocatedMeasure(f.productId())),f.referenceMeasure()); }
    UUID insert(UUID product,UUID parent,BigDecimal length,BigDecimal width,BigDecimal height,String location) {
        UUID id=UUID.randomUUID();
        db.update("INSERT INTO retazos.piece(id,product_id,parent_id,length_m,width_cm,height_cm,location) VALUES (?,?,?,?,?,?,?)",id,product,parent,length,width,height,location);
        return id;
    }
}
