package com.alumvid.logistica.service;

import com.alumvid.logistica.dto.*;
import java.util.List;
import java.util.UUID;

/**
 * Logística: rutas, paradas, choferes en ruta y prueba de entrega.
 * Las paradas nacen de pedidos comerciales; la custodia del material la lleva pedidos.
 */
public interface LogisticaService {

    // Choferes (identidad en usuarios; disponibilidad calculada aquí)
    List<ChoferResponse> listarChoferes();

    // Planificación (administración)
    RutaResponse crearRuta(CrearRutaSimpleRequest request);
    RutaResponse agregarPedidos(UUID rutaId, AgregarPedidosRequest request);
    RutaResponse modificarCarga(UUID rutaId, UUID despachoId, ModificarCargaRequest request);
    RutaResponse eliminarDestinoRuta(UUID rutaId, UUID despachoId);
    RutaResponse asignarChoferRuta(UUID rutaId, UUID choferId);
    void eliminarRuta(UUID rutaId);
    RutaResponse aceptarEIniciarRutaConsolidada(UUID rutaId);
    RutaResponse cancelarRutaConsolidada(UUID rutaId, String motivo);
    RutaResponse completarRutaConsolidada(UUID rutaId);

    // Consulta
    List<RutaResponse> listarRutas();
    List<RutaResponse> listarRutasPorChofer(UUID choferId);
    RutaResponse obtenerRutaPorId(UUID rutaId);
    List<DespachoResponse> listarDespachos();
    List<DespachoResponse> listarDespachosHoyChofer(UUID choferId);
    EvidenciaPodResponse obtenerEvidenciaPod(UUID despachoId);

    // Operación del chofer en ruta
    DespachoResponse aceptarEIniciarRuta(UUID despachoId);
    DespachoResponse cancelarRuta(UUID despachoId, String motivo);
    DespachoResponse cerrarEntrega(UUID despachoId, CerrarEntregaRequest request);
    DespachoResponse reintentarParada(UUID despachoId);
    RutaResponse optimizarRutaPorChofer(UUID rutaId, Double latChofer, Double lonChofer);

    // Propiedad (para validar que un chofer opere solo lo suyo)
    UUID choferDeRuta(UUID rutaId);
    UUID choferDeDespacho(UUID despachoId);
}
