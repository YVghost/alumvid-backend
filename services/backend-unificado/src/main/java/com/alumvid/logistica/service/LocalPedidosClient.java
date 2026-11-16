package com.alumvid.logistica.service;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import com.alumvid.pedidos.LocalPedidosFacade;
import org.springframework.stereotype.Component;

/** Same operations and permission checks as the remote client, without loopback HTTP. */
@Component
public class LocalPedidosClient extends PedidosClient {
    private final LocalPedidosFacade facade;
    public LocalPedidosClient(LocalPedidosFacade facade){super();this.facade=facade;}
    @Override public Map<String,Object> despachar(UUID order,UUID driver,UUID route,UUID dispatch,UUID destination,List<Map<String,Object>> lines,String reason){return facade.dispatch(order,driver,route,dispatch,destination,lines,reason);}
    @Override public void anular(UUID shipment,String reason){facade.release(shipment,reason);}
    @Override public void reasignarChofer(UUID route,UUID driver){facade.reassign(route,driver);}
    @Override public Map<String,Object> pedido(UUID order){return facade.order(order);}
}
