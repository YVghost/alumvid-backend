package com.alumvid.logistica;

import com.alumvid.logistica.dto.*;
import com.alumvid.logistica.model.*;
import com.alumvid.logistica.service.LogisticaService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@Transactional
class LogisticaServiceTests {

    @Autowired
    private LogisticaService logisticaService;

    @Test
    @DisplayName("HU-04: Asignacion de ruta, consentimiento del chofer y cierre exitoso e-PoD")
    void testFlujoCompletoConConsentimiento() {
        ChoferResponse chofer = logisticaService.sincronizarOCrearChofer(SincronizarChoferRequest.builder()
                .id(UUID.randomUUID())
                .nombre("Chofer Test 1")
                .email("chofer1.test@alumvid.com")
                .telefono("+593988888888")
                .build());

        PedidoResponse pedido = logisticaService.crearPedido(CrearPedidoRequest.builder()
                .cliente("Vidrieria Modelo")
                .direccionTexto("Av. Amazonas y Orellana, Quito")
                .latitud(-0.1807)
                .longitud(-78.4678)
                .build());

        // 1. Asignar ruta (queda en estado PENDIENTE de aprobacion del chofer)
        DespachoResponse despacho = logisticaService.asignarDespacho(AsignarDespachoRequest.builder()
                .pedidoId(pedido.getId())
                .choferId(chofer.getId())
                .build());

        assertEquals(EstadoDespacho.PENDIENTE, despacho.getEstado());

        // 2. Chofer otorga consentimiento expreso para iniciar el viaje
        despacho = logisticaService.aceptarEIniciarRuta(despacho.getId());
        assertEquals(EstadoDespacho.EN_CURSO, despacho.getEstado());

        // 3. Chofer cierra entrega con foto, firma y GPS en sitio
        CerrarEntregaRequest cierre = CerrarEntregaRequest.builder()
                .fotoPodUrl("https://storage.alumvid.com/pod/evidencia.jpg")
                .firmaUrl("data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==")
                .latitud(-0.1807)
                .longitud(-78.4678)
                .comentarios("Entregado conforme.")
                .build();

        DespachoResponse cerrado = logisticaService.cerrarEntrega(despacho.getId(), cierre);
        assertEquals(EstadoDespacho.ENTREGADO, cerrado.getEstado());
        assertFalse(cerrado.getAlertaDesviacion());
        assertTrue(cerrado.getDesviacionMetros() < 10.0);
    }

    @Test
    @DisplayName("Cancelacion voluntaria de ruta por parte del chofer con corte de streaming")
    void testCancelacionRutaPorChofer() {
        ChoferResponse chofer = logisticaService.sincronizarOCrearChofer(SincronizarChoferRequest.builder()
                .id(UUID.randomUUID())
                .nombre("Chofer Cancelacion")
                .email("cancel.chofer@alumvid.com")
                .build());

        PedidoResponse pedido = logisticaService.crearPedido(CrearPedidoRequest.builder()
                .cliente("Cliente Cancelado")
                .direccionTexto("Av. 6 de Diciembre")
                .latitud(-0.1900)
                .longitud(-78.4700)
                .build());

        DespachoResponse despacho = logisticaService.asignarDespacho(AsignarDespachoRequest.builder()
                .pedidoId(pedido.getId())
                .choferId(chofer.getId())
                .build());

        despacho = logisticaService.aceptarEIniciarRuta(despacho.getId());
        assertEquals(EstadoDespacho.EN_CURSO, despacho.getEstado());

        // Chofer cancela la ruta
        DespachoResponse cancelado = logisticaService.cancelarRuta(despacho.getId(), "Falla mecanica en el vehiculo.");
        assertEquals(EstadoDespacho.CANCELADA, cancelado.getEstado());
        assertEquals(EstadoPedido.CANCELADO, cancelado.getPedido().getEstado());
        assertEquals(EstadoChofer.DISPONIBLE, cancelado.getChofer().getEstadoDisponibilidad());
    }

    @Test
    @DisplayName("CP-LOG-02: Deteccion de desvio geografico > 500m con alerta de auditoria PostGIS")
    void testAlertaDesviacionGeografica() {
        ChoferResponse chofer = logisticaService.sincronizarOCrearChofer(SincronizarChoferRequest.builder()
                .id(UUID.randomUUID())
                .nombre("Chofer Desvio")
                .email("desvio@alumvid.com")
                .build());

        PedidoResponse pedido = logisticaService.crearPedido(CrearPedidoRequest.builder()
                .cliente("Destino Quito Norte")
                .direccionTexto("Av. Amazonas y Orellana")
                .latitud(-0.1807)
                .longitud(-78.4678)
                .build());

        DespachoResponse despacho = logisticaService.asignarDespacho(AsignarDespachoRequest.builder()
                .pedidoId(pedido.getId())
                .choferId(chofer.getId())
                .build());

        logisticaService.aceptarEIniciarRuta(despacho.getId());

        // Entrega en Cumbaya (-0.2035, -78.4350) a mas de 4000m
        CerrarEntregaRequest cierreDesvio = CerrarEntregaRequest.builder()
                .fotoPodUrl("https://storage.alumvid.com/pod/foto.jpg")
                .firmaUrl("data:image/png;base64,firma")
                .latitud(-0.2035)
                .longitud(-78.4350)
                .build();

        DespachoResponse cerrado = logisticaService.cerrarEntrega(despacho.getId(), cierreDesvio);
        assertTrue(cerrado.getAlertaDesviacion(), "Debe activar alerta de desvio al superar 500m");
        assertTrue(cerrado.getDesviacionMetros() > 500.0);
    }

    @Test
    @DisplayName("CP-LOG-01: Rechazo si falta foto, firma o telemetria GPS")
    void testRechazoSinEvidencias() {
        ChoferResponse chofer = logisticaService.sincronizarOCrearChofer(SincronizarChoferRequest.builder()
                .id(UUID.randomUUID())
                .nombre("Chofer Sin Evidencia")
                .email("sinevidencia@alumvid.com")
                .build());

        PedidoResponse pedido = logisticaService.crearPedido(CrearPedidoRequest.builder()
                .cliente("Cliente Test")
                .direccionTexto("Direccion Test")
                .latitud(-0.1800)
                .longitud(-78.4600)
                .build());

        DespachoResponse despacho = logisticaService.asignarDespacho(AsignarDespachoRequest.builder()
                .pedidoId(pedido.getId())
                .choferId(chofer.getId())
                .build());

        logisticaService.aceptarEIniciarRuta(despacho.getId());

        assertThrows(IllegalArgumentException.class, () ->
                logisticaService.cerrarEntrega(despacho.getId(), CerrarEntregaRequest.builder()
                        .fotoPodUrl("")
                        .firmaUrl("firma_ok")
                        .latitud(-0.1800)
                        .longitud(-78.4600)
                        .build())
        );
    }
}
