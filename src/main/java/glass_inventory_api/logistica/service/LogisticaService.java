package glass_inventory_api.logistica.service;

import glass_inventory_api.logistica.dto.*;

import java.util.List;
import java.util.UUID;

public interface LogisticaService {

    PedidoResponse crearPedido(CrearPedidoRequest request);

    List<PedidoResponse> listarPedidos();

    List<PedidoResponse> listarPedidosPendientes();

    ChoferResponse crearChofer(String nombre, String email, String telefono);

    List<ChoferResponse> listarChoferes();

    DespachoResponse asignarDespacho(AsignarDespachoRequest request);

    List<DespachoResponse> listarTodosDespachos();

    List<DespachoResponse> listarDespachosPorChofer(UUID choferId);

    DespachoResponse iniciarRuta(UUID despachoId);

    DespachoResponse cerrarEntrega(UUID despachoId, CerrarEntregaRequest request);

    EvidenciaPodResponse obtenerEvidencia(UUID despachoId);
}
