package com.alumvid.pedidos;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.alumvid.logistica.security.Sesion;
import jakarta.validation.Validator;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/** Module boundary: reuse pedidos business services, never write their tables from logistics. */
@Component
public class LocalPedidosFacade {
    private final CommercialShipments shipments;
    private final PedidosService orders;
    private final LocalPedidosAuthClient auth;
    private final Validator validator;
    private final ObjectMapper json;
    public LocalPedidosFacade(CommercialShipments shipments,PedidosService orders,LocalPedidosAuthClient auth,Validator validator,ObjectMapper json) {
        this.shipments=shipments;this.orders=orders;this.auth=auth;this.validator=validator;this.json=json;
    }
    private AuthClient.Identity actor(boolean write) {
        var actor=auth.identity(Sesion.token());
        if(actor.mustChangePassword() || (write ? !actor.has("ADMINISTRADOR")&&!actor.has("BODEGUERO") : !actor.has("ADMINISTRADOR")&&!actor.has("BODEGUERO")&&!actor.has("VENDEDOR")&&!actor.has("CHOFER")))
            throw new ResponseStatusException(HttpStatusCode.valueOf(403),"Sin permisos para pedidos");
        return actor;
    }
    private <T> T validate(T request) {
        if(!validator.validate(request).isEmpty()) throw new ResponseStatusException(HttpStatusCode.valueOf(400),"Solicitud inválida para pedidos");
        return request;
    }
    private ResponseStatusException error(PedidosError error) {return new ResponseStatusException(HttpStatusCode.valueOf(error.status),error.getMessage());}
    // REQUIRES_NEW preserves the original HTTP boundary and its compensation behavior.
    @Transactional(propagation=Propagation.REQUIRES_NEW)
    public Map<String,Object> dispatch(UUID order,UUID driver,UUID route,UUID dispatch,UUID destination,List<Map<String,Object>> lines,String reason) {
        try {
            var parsed=lines==null||lines.isEmpty()?null:lines.stream().map(line->json.convertValue(line,PedidosApi.BatchLine.class)).toList();
            var request=validate(new CommercialShipments.Create(UUID.nameUUIDFromBytes(("logistica:"+dispatch).getBytes(java.nio.charset.StandardCharsets.UTF_8)),driver,route,dispatch,destination,parsed,reason,null));
            return shipments.create(order,request,actor(false));
        } catch(PedidosError e){throw error(e);}
    }
    @Transactional(propagation=Propagation.REQUIRES_NEW)
    public void release(UUID shipment,String reason) {
        try {shipments.release(shipment,validate(new PedidosApi.Action(UUID.randomUUID(),reason)),actor(false));}catch(PedidosError e){throw error(e);}
    }
    @Transactional(propagation=Propagation.REQUIRES_NEW)
    public void reassign(UUID route,UUID driver) {
        try {
            var actor=actor(true);if(!actor.has("ADMINISTRADOR"))throw new ResponseStatusException(HttpStatusCode.valueOf(403),"Solo administración reasigna choferes");
            shipments.reassign(validate(new CommercialShipments.Reassign(route,driver)),actor);
        }catch(PedidosError e){throw error(e);}
    }
    public Map<String,Object> order(UUID order) {
        actor(false);try{return orders.get(order);}catch(PedidosError e){throw error(e);}
    }
}
