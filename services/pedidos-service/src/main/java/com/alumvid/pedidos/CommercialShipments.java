package com.alumvid.pedidos;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;

@Service
class CommercialShipments {
    /** Lo invoca logística al armar una ruta: los identificadores de ruta y parada los genera logística. */
    record Create(@NotNull UUID requestId,@NotNull UUID driverId,@NotNull UUID routeId,@NotNull UUID dispatchId,@NotNull UUID logisticsOrderId,
        @Size(min=1,max=50) @Valid List<PedidosApi.BatchLine> lines,
        @NotBlank @Size(max=500) String reason,@Size(max=150) String receiverName) {}
    record Reassign(@NotNull UUID routeId,@NotNull UUID driverId) {}
    private final JdbcTemplate db; private final PedidosService orders; private final OrderFulfillment fulfillment; private final ObjectMapper json;
    CommercialShipments(JdbcTemplate db,PedidosService orders,OrderFulfillment fulfillment,ObjectMapper json){this.db=db;this.orders=orders;this.fulfillment=fulfillment;this.json=json;}
    private void permission(AuthClient.Identity actor){if(!actor.has("ADMINISTRADOR")&&!actor.has("BODEGUERO"))throw new PedidosError(403,"Solo administración y bodega despachan o reciben material");}
    List<Map<String,Object>> drivers(){return db.queryForList("SELECT id,full_name FROM usuarios.app_user WHERE active AND NOT must_change_password AND 'CHOFER'=ANY(string_to_array(roles,',')) ORDER BY full_name");}
    List<Map<String,Object>> list(UUID order){return db.queryForList("SELECT * FROM pedidos.commercial_shipment WHERE order_id=? ORDER BY created_at,id",order);}
    private Map<String,Object> get(UUID id){return db.queryForMap("SELECT * FROM pedidos.commercial_shipment WHERE id=?",id);}
    private Map<String,Object> driver(UUID id){
        var drivers=db.queryForList("SELECT id,full_name,email,telefono FROM usuarios.app_user WHERE id=? AND active AND NOT must_change_password AND 'CHOFER'=ANY(string_to_array(roles,','))",id);
        if(drivers.isEmpty())throw new PedidosError(409,"El chofer debe estar activo, tener el rol CHOFER y haber cambiado su clave temporal");
        return drivers.getFirst();
    }
    /** Despacho con todo lo necesario para que logística arme la parada. */
    private Map<String,Object> detail(UUID shipment){
        var s=new LinkedHashMap<String,Object>(get(shipment));
        s.put("order",db.queryForMap("SELECT o.id,o.number,o.client_name,o.delivery_address,o.receiver_name,o.delivery_latitude,o.delivery_longitude,o.state,c.phone AS client_phone FROM pedidos.sale_order o LEFT JOIN pedidos.client c ON c.id=o.client_id WHERE o.id=?",s.get("order_id")));
        s.put("items",items(shipment));
        return s;
    }
    List<Map<String,Object>> items(UUID shipment){
        return db.queryForList("SELECT l.id AS line_id,l.product_id,l.product_code,l.product_name,i.quantity,COALESCE(p.length_m,l.length_m) AS length_m,COALESCE(p.width_cm,l.width_cm) AS width_cm,COALESCE(p.height_cm,l.height_cm) AS height_cm,f.piece_id FROM pedidos.shipment_item i JOIN pedidos.fulfillment_item f ON f.id=i.fulfillment_id JOIN pedidos.order_line l ON l.id=f.line_id LEFT JOIN retazos.piece p ON p.id=f.piece_id WHERE i.shipment_id=? ORDER BY l.position,f.id",shipment);
    }
    /** Lo que ya está preparado en bodega y aún no sale (por línea). */
    private List<PedidosApi.BatchLine> readyLines(UUID order){
        return db.queryForList("SELECT line_id,SUM(quantity-delivered_quantity-returned_quantity-dispatched_quantity) AS ready FROM pedidos.fulfillment_item WHERE order_id=? GROUP BY line_id HAVING SUM(quantity-delivered_quantity-returned_quantity-dispatched_quantity)>0",order)
            .stream().map(r->new PedidosApi.BatchLine((UUID)r.get("line_id"),(BigDecimal)r.get("ready"))).toList();
    }
    @Transactional
    public Map<String,Object> create(UUID order,Create request,AuthClient.Identity actor){
        permission(actor);
        String fingerprint;
        try{fingerprint=order+":"+actor.id()+":"+json.writeValueAsString(request);}catch(Exception e){throw new IllegalStateException(e);}
        db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0)) IS NULL",Boolean.class,request.requestId().toString());
        var old=db.queryForList("SELECT * FROM pedidos.commercial_shipment WHERE request_id=?",request.requestId());
        if(!old.isEmpty()){if(!fingerprint.equals(old.getFirst().get("fingerprint")))throw new PedidosError(409,"requestId ya utilizado con otro despacho");return detail((UUID)old.getFirst().get("id"));}
        var found=db.queryForList("SELECT * FROM pedidos.sale_order WHERE id=? FOR UPDATE",order);
        if(found.isEmpty())throw new PedidosError(404,"Pedido no encontrado");var sale=found.getFirst();
        if(!"ENTREGA".equals(sale.get("delivery_mode")))throw new PedidosError(409,"Pedido para retiro en local");
        driver(request.driverId());
        // Pedido completo: si no se indica la carga se despacha todo lo preparado que sigue en bodega.
        List<PedidosApi.BatchLine> lines=request.lines()!=null?request.lines():readyLines(order);
        if(lines.isEmpty())throw new PedidosError(409,"El pedido #"+sale.get("number")+" aún no tiene material preparado para despachar");
        Map<UUID,BigDecimal> selection=new LinkedHashMap<>();
        for(var line:lines)if(selection.put(line.lineId(),line.quantity())!=null)throw new PedidosError(400,"Línea repetida");
        Map<UUID,BigDecimal> items=new LinkedHashMap<>();
        for(var line:selection.entrySet()){
            BigDecimal need=line.getValue();
            for(var f:db.queryForList("SELECT * FROM pedidos.fulfillment_item WHERE order_id=? AND line_id=? ORDER BY created_at,id FOR UPDATE",order,line.getKey())){
                BigDecimal available=((BigDecimal)f.get("quantity")).subtract((BigDecimal)f.get("delivered_quantity")).subtract((BigDecimal)f.get("returned_quantity")).subtract((BigDecimal)f.get("dispatched_quantity"));
                BigDecimal take=need.min(available);if(take.signum()>0){items.put((UUID)f.get("id"),take);need=need.subtract(take);}if(need.signum()==0)break;
            }
            if(need.signum()>0)throw new PedidosError(409,"La cantidad supera lo preparado en bodega");
        }
        UUID shipment=UUID.randomUUID();
        UUID actionId=UUID.nameUUIDFromBytes(("shipment:"+request.requestId()).getBytes(StandardCharsets.UTF_8));
        orders.action(order,"dispatch",new PedidosApi.Action(actionId,request.reason(),lines,request.receiverName()),actor);
        db.update("INSERT INTO pedidos.commercial_shipment(id,order_id,request_id,fingerprint,driver_id,logistics_order_id,dispatch_id,route_id,receiver_name,reason,created_by,created_by_name) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",shipment,order,request.requestId(),fingerprint,request.driverId(),request.logisticsOrderId(),request.dispatchId(),request.routeId(),PedidosService.text(request.receiverName()),request.reason(),actor.id(),actor.fullName());
        for(var item:items.entrySet())db.update("INSERT INTO pedidos.shipment_item(shipment_id,fulfillment_id,quantity) VALUES (?,?,?)",shipment,item.getKey(),item.getValue());
        return detail(shipment);
    }
    /** Anula un despacho cuya ruta no ha salido: el material vuelve a quedar preparado en bodega. */
    @Transactional
    public Map<String,Object> release(UUID shipment,PedidosApi.Action action,AuthClient.Identity actor){
        permission(actor);
        var ref=db.queryForList("SELECT order_id FROM pedidos.commercial_shipment WHERE id=?",shipment);if(ref.isEmpty())throw new PedidosError(404,"Despacho comercial no encontrado");
        UUID order=(UUID)ref.getFirst().get("order_id");var sale=db.queryForMap("SELECT * FROM pedidos.sale_order WHERE id=? FOR UPDATE",order);
        var s=db.queryForMap("SELECT * FROM pedidos.commercial_shipment WHERE id=? FOR UPDATE",shipment);
        if("DEVUELTO_BODEGA".equals(s.get("state")))return get(shipment);
        if(!"EN_REPARTO".equals(s.get("state")))throw new PedidosError(409,"Solo se anula un despacho que aún no fue entregado ni devuelto");
        var rows=db.queryForList("SELECT fulfillment_id,quantity FROM pedidos.shipment_item WHERE shipment_id=? ORDER BY fulfillment_id",shipment);
        for(var row:rows)if(db.update("UPDATE pedidos.fulfillment_item SET dispatched_quantity=dispatched_quantity-? WHERE id=? AND dispatched_quantity>=?",row.get("quantity"),row.get("fulfillment_id"),row.get("quantity"))!=1)throw new PedidosError(409,"Custodia inconsistente");
        if(!Set.of("CANCELADO","VENCIDO","ENTREGADO").contains(sale.get("state").toString())){
            String next=fulfillment.refresh(order);
            if("RETRASADO".equals(sale.get("state")))db.update("UPDATE pedidos.sale_order SET resume_state=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",next,order);
            else db.update("UPDATE pedidos.sale_order SET state=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",next,order);
        }
        db.update("UPDATE pedidos.commercial_shipment SET state='DEVUELTO_BODEGA',returned_at=CURRENT_TIMESTAMP WHERE id=?",shipment);
        db.update("INSERT INTO pedidos.order_event(id,order_id,action,reason,actor_id,actor_name,detail) VALUES (?,?,'DESPACHO_ANULADO',?,?,?,jsonb_build_object('shipmentId',?::text))",UUID.randomUUID(),order,action.reason(),actor.id(),actor.fullName(),shipment.toString());
        return get(shipment);
    }
    /** Cambio de chofer de una ruta que aún no inicia. */
    @Transactional
    public Map<String,Object> reassign(Reassign request,AuthClient.Identity actor){
        if(!actor.has("ADMINISTRADOR"))throw new PedidosError(403,"Solo administración asigna choferes");
        driver(request.driverId());
        int n=db.update("UPDATE pedidos.commercial_shipment SET driver_id=? WHERE route_id=? AND state='EN_REPARTO'",request.driverId(),request.routeId());
        return Map.of("updated",n);
    }
    /** Bandeja de entregas: pedidos a domicilio con material por enviar. */
    List<Map<String,Object>> pendingDeliveries(){
        return db.queryForList("SELECT * FROM ("
            +" SELECT o.id,o.number,o.client_name,o.delivery_address,o.receiver_name,o.delivery_latitude,o.delivery_longitude,o.state,o.total,o.expires_at,o.created_at,c.phone AS client_phone,"
            +" (SELECT COALESCE(SUM(f.quantity-f.delivered_quantity-f.returned_quantity-f.dispatched_quantity),0) FROM pedidos.fulfillment_item f WHERE f.order_id=o.id) AS ready_quantity,"
            +" (SELECT COALESCE(SUM(l.quantity-l.prepared_quantity),0) FROM pedidos.order_line l WHERE l.order_id=o.id) AS pending_preparation,"
            +" (SELECT COALESCE(SUM(f.dispatched_quantity),0) FROM pedidos.fulfillment_item f WHERE f.order_id=o.id) AS in_transit"
            +" FROM pedidos.sale_order o LEFT JOIN pedidos.client c ON c.id=o.client_id"
            +" WHERE o.delivery_mode='ENTREGA' AND o.state IN ('RESERVADO','PENDIENTE_MATERIAL','PARCIAL','LISTO','EN_REPARTO','RETRASADO')"
            +") d WHERE d.ready_quantity>0 OR d.pending_preparation>0"
            +" ORDER BY (d.ready_quantity>0 AND d.state IN ('PARCIAL','LISTO','EN_REPARTO')) DESC,d.expires_at,d.number");
    }
    @Transactional
    public Map<String,Object> receive(UUID shipment,PedidosApi.Action action,AuthClient.Identity actor){
        permission(actor);
        var ref=db.queryForList("SELECT order_id FROM pedidos.commercial_shipment WHERE id=?",shipment);if(ref.isEmpty())throw new PedidosError(404,"Despacho comercial no encontrado");
        UUID order=(UUID)ref.getFirst().get("order_id");var sale=db.queryForMap("SELECT * FROM pedidos.sale_order WHERE id=? FOR UPDATE",order);
        var s=db.queryForMap("SELECT * FROM pedidos.commercial_shipment WHERE id=? FOR UPDATE",shipment);
        if("DEVUELTO_BODEGA".equals(s.get("state")))return s;
        if(!"RETORNO_PENDIENTE".equals(s.get("state")))throw new PedidosError(409,"Primero cancela el reparto para registrar su retorno físico");
        var rows=db.queryForList("SELECT f.id,f.line_id,f.product_id,i.quantity FROM pedidos.shipment_item i JOIN pedidos.fulfillment_item f ON f.id=i.fulfillment_id WHERE shipment_id=? ORDER BY f.id",shipment);
        rows.stream().map(x->(UUID)x.get("product_id")).distinct().sorted().forEach(id->db.queryForList("SELECT id FROM inventario.product WHERE id=? FOR UPDATE",id));
        boolean closed=Set.of("CANCELADO","VENCIDO").contains(sale.get("state").toString());
        if(closed){
            Map<UUID,BigDecimal> quantities=new LinkedHashMap<>();Map<UUID,BigDecimal> byLine=new LinkedHashMap<>();
            for(var row:rows){quantities.put((UUID)row.get("id"),(BigDecimal)row.get("quantity"));byLine.merge((UUID)row.get("line_id"),(BigDecimal)row.get("quantity"),BigDecimal::add);}
            var lines=byLine.entrySet().stream().map(e->new PedidosApi.BatchLine(e.getKey(),e.getValue())).toList();
            fulfillment.returnShipment(order,new PedidosApi.Action(action.requestId(),action.reason(),lines,action.receiverName()),actor,quantities);
        }else{
            for(var row:rows)if(db.update("UPDATE pedidos.fulfillment_item SET dispatched_quantity=dispatched_quantity-? WHERE id=? AND dispatched_quantity>=?",row.get("quantity"),row.get("id"),row.get("quantity"))!=1)throw new PedidosError(409,"Custodia inconsistente");
            String next=fulfillment.refresh(order);
            if("RETRASADO".equals(sale.get("state")))db.update("UPDATE pedidos.sale_order SET resume_state=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",next,order);
            else db.update("UPDATE pedidos.sale_order SET state=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",next,order);
        }
        db.update("UPDATE pedidos.commercial_shipment SET state='DEVUELTO_BODEGA',returned_at=CURRENT_TIMESTAMP WHERE id=?",shipment);
        db.update("INSERT INTO pedidos.order_event(id,order_id,action,reason,actor_id,actor_name,detail) VALUES (?,?, 'RECEPCION_REPARTO',?,?,?,jsonb_build_object('shipmentId',?::text,'returnedToStock',?))",UUID.randomUUID(),order,action.reason(),actor.id(),actor.fullName(),shipment.toString(),closed);
        return get(shipment);
    }
}

@RestController
@RequestMapping("/api/pedidos")
class CommercialShipmentsApi {
    private final CommercialShipments service;
    CommercialShipmentsApi(CommercialShipments service){this.service=service;}
    @GetMapping("/shipping-drivers") Object drivers(){return service.drivers();}
    @GetMapping("/orders/{id}/shipments") Object list(@PathVariable UUID id){return service.list(id);}
    @PostMapping("/orders/{id}/shipments") Object create(@PathVariable UUID id,@Valid @RequestBody CommercialShipments.Create request,@AuthenticationPrincipal AuthClient.Identity actor){return service.create(id,request,actor);}
    @PostMapping("/shipments/{id}/receive-return") Object receive(@PathVariable UUID id,@Valid @RequestBody PedidosApi.Action request,@AuthenticationPrincipal AuthClient.Identity actor){return service.receive(id,request,actor);}
    @PostMapping("/shipments/{id}/release") Object release(@PathVariable UUID id,@Valid @RequestBody PedidosApi.Action request,@AuthenticationPrincipal AuthClient.Identity actor){return service.release(id,request,actor);}
    @PutMapping("/shipments/driver") Object reassign(@Valid @RequestBody CommercialShipments.Reassign request,@AuthenticationPrincipal AuthClient.Identity actor){return service.reassign(request,actor);}
    @GetMapping("/shipments/{id}/items") Object items(@PathVariable UUID id){return service.items(id);}
    @GetMapping("/deliveries/pending") Object pending(){return service.pendingDeliveries();}
}
