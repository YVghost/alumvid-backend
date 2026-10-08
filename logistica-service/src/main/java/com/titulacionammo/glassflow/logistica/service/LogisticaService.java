package com.titulacionammo.glassflow.logistica.service;

import com.titulacionammo.glassflow.logistica.dto.*;

import java.util.List;
import java.util.UUID;

/**
 * Contrato de logica de negocio para logistica, asignacion y control de rutas de choferes.
 */
public interface LogisticaService {

    PedidoResponse crearPedido(CrearPedidoRequest request);

    List<PedidoResponse> listarPedidos();

    List<PedidoResponse> listarPedidosPendientes();

    ChoferResponse sincronizarOCrearChofer(SincronizarChoferRequest request);

    List<ChoferResponse> listarChoferes();

    DespachoResponse asignarDespacho(AsignarDespachoRequest request);

    DespachoResponse aceptarEIniciarRuta(UUID despachoId);

    DespachoResponse cancelarRuta(UUID despachoId, String motivo);

    DespachoResponse cerrarEntrega(UUID despachoId, CerrarEntregaRequest request);

    List<DespachoResponse> listarDespachos();

    List<DespachoResponse> listarDespachosHoyChofer(UUID choferId);

    EvidenciaPodResponse obtenerEvidenciaPod(UUID despachoId);

    RutaResponse crearRutaConsolidada(CrearRutaConsolidadaRequest request);

    RutaResponse crearRutaMultiDestino(CrearRutaMultiDestinoRequest request);

    List<RutaResponse> listarRutas();

    List<RutaResponse> listarRutasPorChofer(UUID choferId);

    RutaResponse obtenerRutaPorId(UUID rutaId);

    RutaResponse aceptarEIniciarRutaConsolidada(UUID rutaId);

    RutaResponse cancelarRutaConsolidada(UUID rutaId, String motivo);

    RutaResponse crearRuta(CrearRutaSimpleRequest request);

    RutaResponse asignarChoferRuta(UUID rutaId, UUID choferId);

    RutaResponse agregarDestinoRuta(UUID rutaId, DestinoRutaRequest request);

    RutaResponse modificarDestinoRuta(UUID rutaId, UUID despachoId, DestinoRutaRequest request);

    RutaResponse eliminarDestinoRuta(UUID rutaId, UUID despachoId);

    RutaResponse optimizarRuta(UUID rutaId);

    void eliminarRuta(UUID rutaId);

    void eliminarChofer(UUID choferId);
}
