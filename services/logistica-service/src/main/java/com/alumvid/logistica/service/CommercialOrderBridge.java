package com.alumvid.logistica.service;

import java.util.*;
import java.net.http.HttpClient;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.*;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.web.server.ResponseStatusException;

/** Contrato para una única base compartida: JDBC participa en la transacción JPA de logística. */
@Component
public class CommercialOrderBridge {
    private final JdbcTemplate db; private final RestClient auth;
    public CommercialOrderBridge(JdbcTemplate db,@Value("${AUTH_URL:http://localhost:8081}") String url){
        this.db=db;var f=new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build());f.setReadTimeout(Duration.ofSeconds(3));auth=RestClient.builder().baseUrl(url).requestFactory(f).build();
    }
    private boolean ready(){return Boolean.TRUE.equals(db.queryForObject("SELECT to_regclass('pedidos.commercial_shipment') IS NOT NULL",Boolean.class));}
    private List<Map<String,Object>> find(String column,UUID id){return ready()?db.queryForList("SELECT * FROM pedidos.commercial_shipment WHERE "+column+"=? ORDER BY order_id,id",id):List.of();}
    private void authorize(Map<String,Object> shipment){
        var context=RequestContextHolder.getRequestAttributes();
        if(!(context instanceof ServletRequestAttributes servlet))throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"Se requiere una sesión para operar un despacho comercial");
        String token=servlet.getRequest().getHeader("Authorization");if(token==null||!token.startsWith("Bearer "))throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"Debes iniciar sesión");
        Map<?,?> user;
        try{user=auth.get().uri("/api/auth/me").header("Authorization",token).retrieve().body(Map.class);}
        catch(RestClientResponseException e){throw new ResponseStatusException(e.getStatusCode().value()<500?HttpStatus.UNAUTHORIZED:HttpStatus.SERVICE_UNAVAILABLE,"No se pudo validar la sesión");}
        catch(RestClientException e){throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"Usuarios no disponible");}
        if(user==null||!Boolean.TRUE.equals(user.get("active"))||Boolean.TRUE.equals(user.get("mustChangePassword")))throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Cuenta no habilitada");
        Object roles=user.get("roles");boolean admin=roles instanceof Collection<?> list&&list.contains("ADMINISTRADOR");
        boolean driver=roles instanceof Collection<?> list&&list.contains("CHOFER")&&shipment.get("driver_id").toString().equals(String.valueOf(user.get("id")));
        if(!admin&&!driver)throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Solo el chofer asignado o administración puede operar este despacho");
    }
    public void lock(UUID dispatch,boolean checkOpen){
        var rows=find("dispatch_id",dispatch);if(rows.isEmpty())return;authorize(rows.getFirst());
        db.queryForObject("SELECT pedidos.lock_commercial_dispatch(?)",UUID.class,dispatch);
        if(checkOpen){
            var sale=db.queryForMap("SELECT o.state,o.expires_at>CURRENT_TIMESTAMP AS valid,s.state AS shipment_state FROM pedidos.sale_order o JOIN pedidos.commercial_shipment s ON s.order_id=o.id WHERE s.dispatch_id=?",dispatch);
            if(!Boolean.TRUE.equals(sale.get("valid"))||Set.of("CANCELADO","VENCIDO","RETRASADO").contains(sale.get("state"))||!"EN_REPARTO".equals(sale.get("shipment_state")))throw new ResponseStatusException(HttpStatus.CONFLICT,"Pedido cerrado, retrasado o vencido; revisa el retorno a bodega");
        }
    }
    public void delivered(UUID dispatch){
        if(find("dispatch_id",dispatch).isEmpty())return;
        try{db.queryForObject("SELECT pedidos.complete_commercial_dispatch(?) IS NULL",Boolean.class,dispatch);}
        catch(org.springframework.dao.DataAccessException e){throw new ResponseStatusException(HttpStatus.CONFLICT,"No se puede entregar: revisa el estado, vencimiento y custodia del pedido",e);}
    }
    public void cancelled(UUID dispatch,String reason){if(!find("dispatch_id",dispatch).isEmpty())db.queryForObject("SELECT pedidos.cancel_commercial_dispatch(?,?) IS NULL",Boolean.class,dispatch,reason);}
    public void route(UUID route,boolean open){for(var row:find("route_id",route))lock((UUID)row.get("dispatch_id"),open);}
    public void cancelRoute(UUID route,String reason){for(var row:find("route_id",route))cancelled((UUID)row.get("dispatch_id"),reason);}
    public void immutableRoute(UUID route){if(!find("route_id",route).isEmpty())throw new ResponseStatusException(HttpStatus.CONFLICT,"Ruta comercial vinculada: cancela y recibe su retorno antes de generar otro despacho; no se elimina su historial");}
    public void immutableLogisticsOrder(UUID order){if(!find("logistics_order_id",order).isEmpty())throw new ResponseStatusException(HttpStatus.CONFLICT,"El pedido comercial ya tiene su despacho vinculado");}
    public void immutableDriver(UUID driver){if(!find("driver_id",driver).isEmpty())throw new ResponseStatusException(HttpStatus.CONFLICT,"Chofer con historial de despachos comerciales; desactiva su cuenta sin borrarlo");}
}
