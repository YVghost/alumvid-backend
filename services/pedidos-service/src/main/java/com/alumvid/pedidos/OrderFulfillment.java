package com.alumvid.pedidos;

import java.math.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import static com.alumvid.pedidos.AvailabilityPlanner.*;

/** Custodia fisica: preparado no significa entregado; las salidas se pueden devolver sin recrear la pieza fuente. */
@Component
class OrderFulfillment {
    private final JdbcTemplate db;private final AvailabilityPlanner planner;private final ObjectMapper json;
    OrderFulfillment(JdbcTemplate db,AvailabilityPlanner planner,ObjectMapper json) {this.db=db;this.planner=planner;this.json=json;}
    private String json(Object value) {try{return json.writeValueAsString(value);}catch(Exception e){throw new IllegalStateException(e);}}
    private List<Map<String,Object>> lines(UUID order) {return db.queryForList("SELECT * FROM pedidos.order_line WHERE order_id=? ORDER BY position",order);}
    Map<UUID,BigDecimal> selection(UUID order,PedidosApi.Action action,String mode) {
        var rows=lines(order);Map<UUID,BigDecimal> result=new LinkedHashMap<>();
        if(action.lines()!=null) {
            if(action.lines().isEmpty())throw new PedidosError(400,"Selecciona al menos una cantidad");
            for(var line:action.lines())if(result.put(line.lineId(),line.quantity())!=null)throw new PedidosError(400,"Linea repetida en el lote");
            if(!rows.stream().map(x->uuid(x.get("id"))).toList().containsAll(result.keySet()))throw new PedidosError(400,"La linea no pertenece a este pedido");
        } else {
            for(var line:rows) {
                UUID id=uuid(line.get("id"));BigDecimal available;
                if(mode.equals("prepare"))available=decimal(line.get("quantity")).subtract(decimal(line.get("prepared_quantity")));
                else {
                    String expression=mode.equals("deliverTransit")||mode.equals("receive")?"dispatched_quantity":"quantity-delivered_quantity-returned_quantity-dispatched_quantity";
                    available=db.queryForObject("SELECT COALESCE(SUM("+expression+"),0) FROM pedidos.fulfillment_item WHERE line_id=?",BigDecimal.class,id);
                }
                if(available.signum()>0)result.put(id,available);
            }
        }
        if(result.isEmpty())throw new PedidosError(409,"No hay cantidades disponibles para esta operacion");
        for(var e:result.entrySet())if(e.getValue()==null||e.getValue().signum()<=0)throw new PedidosError(400,"La cantidad debe ser positiva");
        return result;
    }
    void prepare(UUID order,PedidosApi.Action action,AuthClient.Identity actor) {
        var selected=selection(order,action,"prepare");Set<UUID> changed=new TreeSet<>();
        Map<UUID,BigDecimal> before=new HashMap<>();
        for(var item:selected.entrySet()) {
            var line=db.queryForMap("SELECT * FROM pedidos.order_line WHERE id=?",item.getKey());UUID product=uuid(line.get("product_id"));var p=planner.product(product);
            if(!Boolean.TRUE.equals(p.get("active")))throw new PedidosError(409,"Producto inactivo");
            before.putIfAbsent(product,decimal(p.get("stock")));boolean first=changed.add(product);
            BigDecimal need=item.getValue(),remaining=decimal(line.get("quantity")).subtract(decimal(line.get("prepared_quantity")));
            if(need.compareTo(remaining)>0)throw new PedidosError(409,"La preparacion supera la cantidad pendiente");
            boolean managed=Boolean.TRUE.equals(p.get("pieces_managed"));
            if(managed&&need.stripTrailingZeros().scale()>0)throw new PedidosError(400,"Las piezas se preparan en cantidades enteras");
            if(managed&&first)consistent(product,p);
            var allocations=db.queryForList("SELECT id FROM pedidos.allocation WHERE order_id=? AND line_id=? AND state='ACTIVA' ORDER BY created_at,id",order,item.getKey());
            for(var ref:allocations) {
                if(need.signum()==0)break;
                var a=db.queryForMap("SELECT * FROM pedidos.allocation WHERE id=?",ref.get("id"));BigDecimal take=need.min(decimal(a.get("quantity")));
                UUID preparedPiece=null;String location=(String)p.get("location");
                if(managed) {
                    boolean aluminum="ALUMINIO".equals(p.get("kind"));UUID source=uuid(a.get("piece_id"));var piece=db.queryForMap("SELECT * FROM retazos.piece WHERE id=?",source);
                    if(!"DISPONIBLE".equals(piece.get("state")))throw new PedidosError(409,"La pieza reservada ya no esta disponible");
                    BigDecimal used=decimal(a.get("used_extent")),waste=decimal(a.get("waste_extent"));
                    BigDecimal leftover=decimal(piece.get(aluminum?"length_m":"width_cm")).subtract(used).subtract(waste);
                    if(leftover.signum()<0)throw new PedidosError(409,"El corte supera la pieza reservada");
                    location=piece.get("location").toString();
                    db.update("UPDATE retazos.piece SET state=? WHERE id=?",leftover.signum()>0?"TRANSFORMADO":"CONSUMIDO",source);
                    preparedPiece=insertPiece(product,source,aluminum?used:null,aluminum?null:used,(BigDecimal)piece.get("height_cm"),location,"PREPARADO");
                    db.update("UPDATE pedidos.allocation SET state='CONSUMIDA' WHERE id=?",a.get("id"));
                    UUID rest=null;
                    if(leftover.signum()>0)rest=insertPiece(product,source,aluminum?leftover:null,aluminum?null:leftover,(BigDecimal)piece.get("height_cm"),location,"DISPONIBLE");
                    long pending=db.queryForObject("SELECT count(*) FROM pedidos.allocation WHERE order_id=? AND piece_id=? AND state='ACTIVA'",Long.class,order,source);
                    if(pending>0) {
                        if(rest==null)throw new PedidosError(409,"El corte no deja material para las demas reservas");
                        db.update("UPDATE pedidos.allocation SET piece_id=? WHERE order_id=? AND piece_id=? AND state='ACTIVA'",rest,order,source);
                        BigDecimal extent=aluminum?leftover:leftover.multiply(decimal(piece.get("height_cm")));
                        BigDecimal reserved=extent.divide(reference(p),12,RoundingMode.DOWN);
                        db.update("UPDATE inventario.stock_reservation SET piece_id=?,quantity=?,updated_at=CURRENT_TIMESTAMP WHERE order_id=? AND piece_id=? AND state='ACTIVA'",rest,reserved,order,source);
                    } else db.update("UPDATE inventario.stock_reservation SET state='CONSUMIDA',updated_at=CURRENT_TIMESTAMP WHERE order_id=? AND piece_id=? AND state='ACTIVA'",order,source);
                } else {
                    BigDecimal allocated=decimal(a.get("quantity"));
                    if(take.compareTo(allocated)==0)db.update("UPDATE pedidos.allocation SET state='CONSUMIDA' WHERE id=?",a.get("id"));
                    else {
                        db.update("UPDATE pedidos.allocation SET quantity=quantity-? WHERE id=?",take,a.get("id"));
                        db.update("INSERT INTO pedidos.allocation(id,order_id,line_id,product_id,quantity,state) VALUES (?,?,?,?,?,'CONSUMIDA')",UUID.randomUUID(),order,item.getKey(),product,take);
                    }
                    consumeGenericReservation(order,product,take);
                    db.update("UPDATE inventario.product SET stock=stock-? WHERE id=?",take,product);
                }
                db.update("INSERT INTO pedidos.fulfillment_item(id,order_id,line_id,product_id,piece_id,quantity,location) VALUES (?,?,?,?,?,?,?)",UUID.randomUUID(),order,item.getKey(),product,preparedPiece,take,location);
                need=need.subtract(take);
            }
            if(need.signum()>0)throw new PedidosError(409,"Falta material reservado para preparar esta cantidad");
            db.update("UPDATE pedidos.order_line SET prepared_quantity=prepared_quantity+? WHERE id=?",item.getValue(),item.getKey());
        }
        for(UUID product:changed) {
            var p=planner.product(product);BigDecimal after=Boolean.TRUE.equals(p.get("pieces_managed"))?physicalStock(product,p):decimal(p.get("stock"));
            movement(order,product,action,actor,before.get(product),after,"PREPARACION_PARCIAL");
        }
    }
    private void consumeGenericReservation(UUID order,UUID product,BigDecimal need) {
        for(var r:db.queryForList("SELECT * FROM inventario.stock_reservation WHERE order_id=? AND product_id=? AND piece_id IS NULL AND state='ACTIVA' ORDER BY created_at,id",order,product)) {
            if(need.signum()==0)break;BigDecimal amount=decimal(r.get("quantity")),take=need.min(amount);
            if(take.compareTo(amount)==0)db.update("UPDATE inventario.stock_reservation SET state='CONSUMIDA',updated_at=CURRENT_TIMESTAMP WHERE id=?",r.get("id"));
            else {db.update("UPDATE inventario.stock_reservation SET quantity=quantity-?,updated_at=CURRENT_TIMESTAMP WHERE id=?",take,r.get("id"));db.update("INSERT INTO inventario.stock_reservation(id,order_id,product_id,quantity,state) VALUES (?,?,?,?,'CONSUMIDA')",UUID.randomUUID(),order,product,take);}
            need=need.subtract(take);
        }
        if(need.signum()>0)throw new PedidosError(409,"Reserva de inventario incompleta");
    }
    void move(UUID order,PedidosApi.Action action,String mode,boolean delivery) {
        String selectionMode=mode.equals("deliver")&&delivery?"deliverTransit":mode;
        for(var selection:selection(order,action,selectionMode).entrySet()) {
            BigDecimal need=selection.getValue();
            boolean transitMode=selectionMode.equals("deliverTransit");
            String balanceExpression=transitMode?"dispatched_quantity":"quantity-delivered_quantity-returned_quantity-dispatched_quantity";
            BigDecimal totalAvailable=db.queryForObject("SELECT COALESCE(SUM("+balanceExpression+"),0) FROM pedidos.fulfillment_item WHERE order_id=? AND line_id=?",BigDecimal.class,order,selection.getKey());
            if(need.compareTo(totalAvailable)>0)throw new PedidosError(409,"La cantidad supera lo preparado o enviado a reparto");
            if(need.stripTrailingZeros().scale()>0&&db.queryForObject("SELECT count(*) FROM pedidos.fulfillment_item WHERE line_id=? AND piece_id IS NOT NULL",Long.class,selection.getKey())>0)throw new PedidosError(400,"Las piezas se entregan completas");
            for(var item:db.queryForList("SELECT * FROM pedidos.fulfillment_item WHERE order_id=? AND line_id=? ORDER BY created_at,id",order,selection.getKey())) {
                if(need.signum()==0)break;
                boolean transit=selectionMode.equals("deliverTransit");
                BigDecimal available=transit?decimal(item.get("dispatched_quantity")):decimal(item.get("quantity")).subtract(decimal(item.get("delivered_quantity"))).subtract(decimal(item.get("returned_quantity"))).subtract(decimal(item.get("dispatched_quantity")));
                BigDecimal take=need.min(available);if(take.signum()<=0)continue;
                if(item.get("piece_id")!=null&&take.compareTo(BigDecimal.ONE)!=0)throw new PedidosError(400,"Las piezas se entregan completas; no se fracciona una pieza ya preparada");
                if(mode.equals("dispatch"))db.update("UPDATE pedidos.fulfillment_item SET dispatched_quantity=dispatched_quantity+? WHERE id=?",take,item.get("id"));
                else {
                    db.update("UPDATE pedidos.fulfillment_item SET delivered_quantity=delivered_quantity+?,dispatched_quantity=dispatched_quantity-? WHERE id=?",take,transit?take:BigDecimal.ZERO,item.get("id"));
                    db.update("UPDATE pedidos.order_line SET delivered_quantity=delivered_quantity+? WHERE id=?",take,selection.getKey());
                    if(item.get("piece_id")!=null)db.update("UPDATE retazos.piece SET state='ENTREGADO' WHERE id=?",item.get("piece_id"));
                }
                need=need.subtract(take);
            }
            if(need.signum()>0)throw new PedidosError(409,"La cantidad supera lo preparado o lo enviado a reparto");
        }
    }
    void returnToStock(UUID order,PedidosApi.Action action,AuthClient.Identity actor,boolean receiveTransit) { returnToStock(order,action,actor,receiveTransit,null); }
    void returnShipment(UUID order,PedidosApi.Action action,AuthClient.Identity actor,Map<UUID,BigDecimal> quantities) { returnToStock(order,action,actor,true,quantities); }
    private void returnToStock(UUID order,PedidosApi.Action action,AuthClient.Identity actor,boolean receiveTransit,Map<UUID,BigDecimal> quantities) {
        Set<UUID> changed=new TreeSet<>();Map<UUID,BigDecimal> before=new HashMap<>();Map<UUID,BigDecimal> generic=new HashMap<>();
        Map<UUID,BigDecimal> selected=receiveTransit?selection(order,action,"receive"):null;
        for(var item:db.queryForList("SELECT * FROM pedidos.fulfillment_item WHERE order_id=? ORDER BY created_at,id",order)) {
            UUID line=uuid(item.get("line_id"));
            BigDecimal amount=receiveTransit?decimal(item.get("dispatched_quantity")):decimal(item.get("quantity")).subtract(decimal(item.get("delivered_quantity"))).subtract(decimal(item.get("returned_quantity"))).subtract(decimal(item.get("dispatched_quantity")));
            if(quantities!=null)amount=amount.min(quantities.getOrDefault(uuid(item.get("id")),BigDecimal.ZERO));
            if(receiveTransit) {amount=amount.min(selected.getOrDefault(line,BigDecimal.ZERO));BigDecimal taken=amount;selected.computeIfPresent(line,(k,v)->v.subtract(taken));}
            if(amount.signum()<=0)continue;
            if(Boolean.TRUE.equals(item.get("legacy_unmeasured")))throw new PedidosError(409,"Pedido antiguo sin medidas de salida: requiere revision fisica antes de devolver");
            UUID product=uuid(item.get("product_id"));var p=planner.product(product);before.putIfAbsent(product,decimal(p.get("stock")));boolean first=changed.add(product);
            if(item.get("piece_id")!=null) {
                if(amount.compareTo(BigDecimal.ONE)!=0)throw new PedidosError(400,"Devuelve la pieza preparada completa");
                if(db.update("UPDATE retazos.piece SET state='DISPONIBLE' WHERE id=? AND state='PREPARADO'",item.get("piece_id"))!=1)throw new PedidosError(409,"La pieza preparada ya cambio de estado");
            } else generic.merge(product,amount,BigDecimal::add);
            db.update("UPDATE pedidos.fulfillment_item SET returned_quantity=returned_quantity+?,dispatched_quantity=dispatched_quantity-? WHERE id=?",amount,receiveTransit?amount:BigDecimal.ZERO,item.get("id"));
            db.update("UPDATE pedidos.order_line SET returned_quantity=returned_quantity+? WHERE id=?",amount,line);
        }
        if(receiveTransit&&selected.values().stream().anyMatch(x->x.signum()>0))throw new PedidosError(409,"No hay esa cantidad pendiente de retorno desde reparto");
        for(UUID product:changed) {
            var p=planner.product(product);BigDecimal after=Boolean.TRUE.equals(p.get("pieces_managed"))?physicalStock(product,p):before.get(product).add(generic.getOrDefault(product,BigDecimal.ZERO));
            movement(order,product,action,actor,before.get(product),after,"DEVOLUCION_PEDIDO");
        }
    }
    String refresh(UUID order) {
        var totals=db.queryForMap("SELECT SUM(quantity) AS total,SUM(prepared_quantity) AS prepared,SUM(delivered_quantity) AS delivered FROM pedidos.order_line WHERE order_id=?",order);
        BigDecimal total=decimal(totals.get("total")),prepared=decimal(totals.get("prepared")),delivered=decimal(totals.get("delivered"));
        BigDecimal transit=db.queryForObject("SELECT COALESCE(SUM(dispatched_quantity),0) FROM pedidos.fulfillment_item WHERE order_id=?",BigDecimal.class,order);
        String state=delivered.compareTo(total)==0?"ENTREGADO":transit.signum()>0?"EN_REPARTO":delivered.signum()>0?"PARCIAL":prepared.compareTo(total)==0?"LISTO":prepared.signum()>0?"PARCIAL":"RESERVADO";
        db.update("UPDATE pedidos.order_line SET state=CASE WHEN delivered_quantity=quantity THEN 'ENTREGADO' WHEN prepared_quantity=quantity THEN 'PREPARADO' WHEN prepared_quantity>0 OR delivered_quantity>0 THEN 'PARCIAL' ELSE state END WHERE order_id=?",order);
        return state;
    }
    private BigDecimal reference(Map<String,Object> p) {return "ALUMINIO".equals(p.get("kind"))?decimal(p.get("full_length_m")):decimal(p.get("full_width_cm")).multiply(decimal(p.get("full_height_cm")));}
    private BigDecimal physicalStock(UUID product,Map<String,Object> p) {return units(db.queryForObject("SELECT COALESCE(SUM(COALESCE(length_m,width_cm*height_cm)),0) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE'",BigDecimal.class,product).add(decimal(p.get("unallocated_measure"))),reference(p));}
    private void consistent(UUID product,Map<String,Object> p) {if(physicalStock(product,p).compareTo(decimal(p.get("stock")))!=0)throw new PedidosError(409,"Stock y piezas no coinciden");}
    private UUID insertPiece(UUID product,UUID parent,BigDecimal length,BigDecimal width,BigDecimal height,String location,String state) {UUID id=UUID.randomUUID();db.update("INSERT INTO retazos.piece(id,product_id,parent_id,length_m,width_cm,height_cm,location,state) VALUES (?,?,?,?,?,?,?,?)",id,product,parent,length,width,height,location,state);return id;}
    private void movement(UUID order,UUID product,PedidosApi.Action action,AuthClient.Identity actor,BigDecimal before,BigDecimal after,String operation) {
        BigDecimal delta=after.subtract(before);if(delta.signum()==0)return;
        if(after.signum()<0||after.precision()-after.scale()>15)throw new PedidosError(409,"Saldo fuera de los limites del inventario");
        UUID id=UUID.randomUUID(),request=UUID.nameUUIDFromBytes(("pedido:"+action.requestId()+":"+product+":"+operation).getBytes(StandardCharsets.UTF_8));
        db.update("INSERT INTO inventario.movement(id,request_id,product_id,type,quantity,delta,stock_before,stock_after,reason,reference,actor_id,actor_name) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",id,request,product,delta.signum()>0?"INGRESO":"SALIDA",delta.abs(),delta,before,after,action.reason().trim(),"pedido:"+order,actor.id(),actor.fullName());
        db.update("UPDATE inventario.product SET stock=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",after,product);
        if(Boolean.TRUE.equals(planner.product(product).get("pieces_managed")))db.update("INSERT INTO retazos.operation(id,product_id,request_id,fingerprint,action,actor_id,actor_name,reason,result) VALUES (?,?,?,?,?,?,?,?,?::jsonb)",UUID.randomUUID(),product,request,request.toString(),operation,actor.id(),actor.fullName(),action.reason().trim(),json(map("orderId",order,"stockBefore",before,"stockAfter",after,"inventoryMovementId",id)));
    }
}
