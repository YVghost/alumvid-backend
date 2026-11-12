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
    record Create(@NotNull UUID requestId,@NotNull UUID driverId,
        @NotNull @DecimalMin("-90") @DecimalMax("90") BigDecimal latitude,
        @NotNull @DecimalMin("-180") @DecimalMax("180") BigDecimal longitude,
        @NotEmpty @Size(max=50) @Valid List<PedidosApi.BatchLine> lines,
        @NotBlank @Size(max=500) String reason,@Size(max=150) String receiverName) {}
    private final JdbcTemplate db; private final PedidosService orders; private final OrderFulfillment fulfillment; private final ObjectMapper json;
    CommercialShipments(JdbcTemplate db,PedidosService orders,OrderFulfillment fulfillment,ObjectMapper json){this.db=db;this.orders=orders;this.fulfillment=fulfillment;this.json=json;}
    private void permission(AuthClient.Identity actor){if(!actor.has("ADMINISTRADOR")&&!actor.has("BODEGUERO"))throw new PedidosError(403,"Solo administración y bodega despachan o reciben material");}
    List<Map<String,Object>> drivers(){return db.queryForList("SELECT id,full_name FROM usuarios.app_user WHERE active AND NOT must_change_password AND 'CHOFER'=ANY(string_to_array(roles,',')) ORDER BY full_name");}
    List<Map<String,Object>> list(UUID order){return db.queryForList("SELECT * FROM pedidos.commercial_shipment WHERE order_id=? ORDER BY created_at,id",order);}
    private Map<String,Object> get(UUID id){return db.queryForMap("SELECT * FROM pedidos.commercial_shipment WHERE id=?",id);}
    @Transactional
    public Map<String,Object> create(UUID order,Create request,AuthClient.Identity actor){
        permission(actor);
        String fingerprint;
        try{fingerprint=order+":"+actor.id()+":"+json.writeValueAsString(request);}catch(Exception e){throw new IllegalStateException(e);}
        db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0)) IS NULL",Boolean.class,request.requestId().toString());
        var old=db.queryForList("SELECT * FROM pedidos.commercial_shipment WHERE request_id=?",request.requestId());
        if(!old.isEmpty()){if(!fingerprint.equals(old.getFirst().get("fingerprint")))throw new PedidosError(409,"requestId ya utilizado con otro despacho");return old.getFirst();}
        var found=db.queryForList("SELECT * FROM pedidos.sale_order WHERE id=? FOR UPDATE",order);
        if(found.isEmpty())throw new PedidosError(404,"Pedido no encontrado");var sale=found.getFirst();
        if(!"ENTREGA".equals(sale.get("delivery_mode")))throw new PedidosError(409,"Pedido para retiro en local");
        if(!Boolean.TRUE.equals(db.queryForObject("SELECT to_regclass('logistica.despachos') IS NOT NULL",Boolean.class)))throw new PedidosError(503,"Logística aún no está inicializada");
        var drivers=db.queryForList("SELECT id,full_name,email,telefono FROM usuarios.app_user WHERE id=? AND active AND NOT must_change_password AND 'CHOFER'=ANY(string_to_array(roles,','))",request.driverId());
        if(drivers.isEmpty())throw new PedidosError(409,"El chofer debe estar activo, tener el rol CHOFER y haber cambiado su clave temporal");var driver=drivers.getFirst();
        Map<UUID,BigDecimal> selection=new LinkedHashMap<>();
        for(var line:request.lines())if(selection.put(line.lineId(),line.quantity())!=null)throw new PedidosError(400,"Línea repetida");
        Map<UUID,BigDecimal> items=new LinkedHashMap<>();
        for(var line:selection.entrySet()){
            BigDecimal need=line.getValue();
            for(var f:db.queryForList("SELECT * FROM pedidos.fulfillment_item WHERE order_id=? AND line_id=? ORDER BY created_at,id FOR UPDATE",order,line.getKey())){
                BigDecimal available=((BigDecimal)f.get("quantity")).subtract((BigDecimal)f.get("delivered_quantity")).subtract((BigDecimal)f.get("returned_quantity")).subtract((BigDecimal)f.get("dispatched_quantity"));
                BigDecimal take=need.min(available);if(take.signum()>0){items.put((UUID)f.get("id"),take);need=need.subtract(take);}if(need.signum()==0)break;
            }
            if(need.signum()>0)throw new PedidosError(409,"La cantidad supera lo preparado en bodega");
        }
        UUID shipment=UUID.randomUUID(),route=UUID.randomUUID(),dispatch=UUID.randomUUID(),logOrder=UUID.randomUUID();
        UUID actionId=UUID.nameUUIDFromBytes(("shipment:"+request.requestId()).getBytes(StandardCharsets.UTF_8));
        orders.action(order,"dispatch",new PedidosApi.Action(actionId,request.reason(),request.lines(),request.receiverName()),actor);
        db.update("INSERT INTO logistica.choferes(id,nombre,email,telefono,estado_disponibilidad,created_at,updated_at) VALUES (?,?,?,?,'DISPONIBLE',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP) ON CONFLICT(id) DO UPDATE SET nombre=EXCLUDED.nombre,email=EXCLUDED.email,telefono=EXCLUDED.telefono",request.driverId(),driver.get("full_name"),driver.get("email"),driver.get("telefono"));
        db.update("INSERT INTO logistica.pedidos(id,cliente,direccion_texto,coordenada_destino,estado,fecha_solicitud,updated_at) VALUES (?,?,?,ST_SetSRID(ST_MakePoint(?,?),4326),'PENDIENTE',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",logOrder,sale.get("client_name"),sale.get("delivery_address"),request.longitude(),request.latitude());
        db.update("INSERT INTO logistica.rutas(id,codigo_ruta,chofer_id,estado,fecha_creacion,comentarios,created_at,updated_at) VALUES (?,?,?,'PENDIENTE',CURRENT_TIMESTAMP,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",route,"PED-"+shipment,request.driverId(),"Pedido comercial #"+sale.get("number"));
        db.update("INSERT INTO logistica.despachos(id,pedido_id,chofer_id,ruta_id,orden_parada,fecha_asignacion,estado,created_at,updated_at) VALUES (?,?,?,?,1,CURRENT_TIMESTAMP,'PENDIENTE',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",dispatch,logOrder,request.driverId(),route);
        db.update("INSERT INTO pedidos.commercial_shipment(id,order_id,request_id,fingerprint,driver_id,logistics_order_id,dispatch_id,route_id,receiver_name,reason,created_by,created_by_name) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",shipment,order,request.requestId(),fingerprint,request.driverId(),logOrder,dispatch,route,PedidosService.text(request.receiverName()),request.reason(),actor.id(),actor.fullName());
        for(var item:items.entrySet())db.update("INSERT INTO pedidos.shipment_item(shipment_id,fulfillment_id,quantity) VALUES (?,?,?)",shipment,item.getKey(),item.getValue());
        return get(shipment);
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
}
