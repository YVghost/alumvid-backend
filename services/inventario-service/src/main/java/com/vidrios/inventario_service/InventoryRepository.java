package com.vidrios.inventario_service;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.*;
import com.fasterxml.jackson.annotation.JsonFormat;
import org.springframework.jdbc.core.*;
import org.springframework.stereotype.Repository;

@Repository
class InventoryRepository {
    enum Unit { UNIDAD, METRO, METRO_CUADRADO, ROLLO, KILOGRAMO, LITRO }
    enum MovementType { INGRESO, SALIDA, AJUSTE }
    record Product(UUID id,String code,String name,String category,Unit unit,String description,String supplier,
        String externalCode,String location,@JsonFormat(shape=JsonFormat.Shape.STRING) BigDecimal minStock,
        @JsonFormat(shape=JsonFormat.Shape.STRING) BigDecimal stock,boolean active,OffsetDateTime createdAt,OffsetDateTime updatedAt) {}
    record Movement(UUID id,UUID requestId,UUID productId,MovementType type,
        @JsonFormat(shape=JsonFormat.Shape.STRING) BigDecimal quantity,@JsonFormat(shape=JsonFormat.Shape.STRING) BigDecimal delta,
        @JsonFormat(shape=JsonFormat.Shape.STRING) BigDecimal stockBefore,@JsonFormat(shape=JsonFormat.Shape.STRING) BigDecimal stockAfter,
        String reason,String reference,UUID actorId,String actorName,OffsetDateTime occurredAt) {}
    record Page<T>(List<T> items,long total,int page,int size) {}
    private final JdbcTemplate db;
    InventoryRepository(JdbcTemplate db) { this.db=db; }
    private final RowMapper<Product> productMapper=(r,n)->new Product(r.getObject("id",UUID.class),r.getString("code"),r.getString("name"),r.getString("category"),Unit.valueOf(r.getString("unit")),r.getString("description"),r.getString("supplier"),r.getString("external_code"),r.getString("location"),r.getBigDecimal("min_stock"),r.getBigDecimal("stock"),r.getBoolean("active"),r.getObject("created_at",OffsetDateTime.class),r.getObject("updated_at",OffsetDateTime.class));
    private final RowMapper<Movement> movementMapper=(r,n)->new Movement(r.getObject("id",UUID.class),r.getObject("request_id",UUID.class),r.getObject("product_id",UUID.class),MovementType.valueOf(r.getString("type")),r.getBigDecimal("quantity"),r.getBigDecimal("delta"),r.getBigDecimal("stock_before"),r.getBigDecimal("stock_after"),r.getString("reason"),r.getString("reference"),r.getObject("actor_id",UUID.class),r.getString("actor_name"),r.getObject("occurred_at",OffsetDateTime.class));
    Product get(UUID id,boolean lock) {
        return db.query("SELECT * FROM inventario.product WHERE id=?"+(lock?" FOR UPDATE":""),productMapper,id).stream().findFirst().orElseThrow(()->new InventoryError(404,"Producto no encontrado"));
    }
    Page<Product> list(String q,String category,boolean includeInactive,boolean lowStock,int page,int size) {
        String where=" WHERE (? OR active=TRUE) AND (?='' OR category=?) AND (?=FALSE OR stock<=min_stock) AND POSITION(? IN LOWER(code || ' ' || name))>0";
        Object[] args={includeInactive,category,category,lowStock,q.toLowerCase(Locale.ROOT)};
        long total=db.queryForObject("SELECT count(*) FROM inventario.product"+where,Long.class,args);
        var params=new ArrayList<>(Arrays.asList(args));params.add(size);params.add((long)page*size);
        var items=db.query("SELECT * FROM inventario.product"+where+" ORDER BY name,id LIMIT ? OFFSET ?",productMapper,params.toArray());
        return new Page<>(items,total,page,size);
    }
    void insert(UUID id,InventoryApi.ProductInput r) {
        db.update("INSERT INTO inventario.product(id,code,name,category,unit,description,supplier,external_code,location,min_stock) VALUES (?,?,?,?,?,?,?,?,?,?)",
            id,r.code().trim().toUpperCase(Locale.ROOT),r.name().trim(),r.category().trim().toUpperCase(Locale.ROOT),r.unit().name(),text(r.description()),text(r.supplier()),text(r.externalCode()),text(r.location()),r.minStock());
    }
    void update(UUID id,InventoryApi.ProductInput r) {
        db.update("UPDATE inventario.product SET name=?,category=?,unit=?,description=?,supplier=?,external_code=?,location=?,min_stock=?,active=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",
            r.name().trim(),r.category().trim().toUpperCase(Locale.ROOT),r.unit().name(),text(r.description()),text(r.supplier()),text(r.externalCode()),text(r.location()),r.minStock(),r.active(),id);
    }
    static String text(String value) { return value==null?"":value.trim(); }
    boolean hasMovements(UUID id) { return db.queryForObject("SELECT count(*) FROM inventario.movement WHERE product_id=?",Long.class,id)>0; }
    Optional<Movement> request(UUID id,UUID requestId) {
        return db.query("SELECT * FROM inventario.movement WHERE product_id=? AND request_id=?",movementMapper,id,requestId).stream().findFirst();
    }
    void movement(UUID id,InventoryApi.MovementInput r,Product p,BigDecimal delta,BigDecimal after,AuthClient.Identity actor) {
        db.update("INSERT INTO inventario.movement(id,request_id,product_id,type,quantity,delta,stock_before,stock_after,reason,reference,actor_id,actor_name) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            id,r.requestId(),p.id(),r.type().name(),r.quantity(),delta,p.stock(),after,r.reason().trim(),text(r.reference()),actor.id(),actor.fullName());
        db.update("UPDATE inventario.product SET stock=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",after,p.id());
    }
    Page<Movement> movements(UUID id,int page,int size) {
        long total=db.queryForObject("SELECT count(*) FROM inventario.movement WHERE product_id=?",Long.class,id);
        return new Page<>(db.query("SELECT * FROM inventario.movement WHERE product_id=? ORDER BY occurred_at DESC,id DESC LIMIT ? OFFSET ?",movementMapper,id,size,(long)page*size),total,page,size);
    }
    void audit(UUID id,AuthClient.Identity actor,String action,String detail) {
        db.update("INSERT INTO inventario.catalog_event(id,product_id,actor_id,actor_name,action,detail) VALUES (?,?,?,?,?,?)",UUID.randomUUID(),id,actor.id(),actor.fullName(),action,detail);
    }
    List<Map<String,Object>> history(UUID id) { return db.queryForList("SELECT id,actor_id,actor_name,action,detail,occurred_at FROM inventario.catalog_event WHERE product_id=? ORDER BY occurred_at DESC,id DESC LIMIT 200",id); }
}
