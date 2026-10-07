package glass_inventory_api;

import glass_inventory_api.logistica.dto.*;
import glass_inventory_api.logistica.model.*;
import glass_inventory_api.logistica.service.LogisticaService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@Transactional
class LogisticaServiceTests {

    @Autowired
    private LogisticaService logisticaService;

    @Test
    @DisplayName("HU-04 / HU-05: Flujo completo de asignación de ruta y cierre con evidencia e-PoD válida")
    void testFlujoCompletoAsignacionYCierrePoD() {
        // 1. Crear chofer
        ChoferResponse chofer = logisticaService.crearChofer("Chofer Test 1", "test1@glassflow.com", "+593988888888");
        assertNotNull(chofer.getId());
        assertEquals(EstadoChofer.DISPONIBLE, chofer.getEstadoDisponibilidad());

        // 2. Crear pedido en Av. Amazonas (-0.1807, -78.4678)
        PedidoResponse pedido = logisticaService.crearPedido(CrearPedidoRequest.builder()
                .cliente("Ventanería La Floresta")
                .direccionTexto("Av. Amazonas y Orellana, Quito")
                .latitud(-0.1807)
                .longitud(-78.4678)
                .build());
        assertNotNull(pedido.getId());
        assertEquals(EstadoPedido.PENDIENTE, pedido.getEstado());

        // 3. Asignar despacho a chofer (HU-04)
        DespachoResponse despacho = logisticaService.asignarDespacho(AsignarDespachoRequest.builder()
                .pedidoId(pedido.getId())
                .choferId(chofer.getId())
                .build());
        assertNotNull(despacho.getId());
        assertEquals(EstadoDespacho.PENDIENTE, despacho.getEstado());
        assertEquals(EstadoPedido.EN_RUTA, despacho.getPedido().getEstado());

        // 4. Iniciar ruta
        despacho = logisticaService.iniciarRuta(despacho.getId());
        assertEquals(EstadoDespacho.EN_RUTA, despacho.getEstado());

        // 5. Chofer cierra entrega con PoD y GPS en la misma ubicación (desviación ~0m)
        CerrarEntregaRequest cierre = CerrarEntregaRequest.builder()
                .fotoPodUrl("https://storage.glassflow.com/pod/foto_entrega_01.jpg")
                .firmaUrl("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
                .latitud(-0.1807)
                .longitud(-78.4678)
                .comentarios("Vidrio entregado en perfectas condiciones y verificado.")
                .build();

        DespachoResponse cerrado = logisticaService.cerrarEntrega(despacho.getId(), cierre);

        // Verificaciones
        assertEquals(EstadoDespacho.ENTREGADO, cerrado.getEstado());
        assertEquals(EstadoPedido.ENTREGADO, cerrado.getPedido().getEstado());
        assertNotNull(cerrado.getFechaEntrega());
        assertNotNull(cerrado.getFotoPodUrl());
        assertNotNull(cerrado.getFirmaUrl());
        assertFalse(cerrado.getAlertaDesviacion(), "No debe haber alerta ya que la entrega fue en la misma coordenada.");
        assertTrue(cerrado.getDesviacionMetros() < 10.0, "La desviación debe ser menor a 10 metros.");
    }

    @Test
    @DisplayName("CP-LOG-02 / RF-04: Detección y alerta de desviación geográfica (> 500m de diferencia)")
    void testAuditoriaDesviacionGeografica_CP_LOG_02() {
        // 1. Crear chofer y pedido en Quito Centro (-0.1807, -78.4678)
        ChoferResponse chofer = logisticaService.crearChofer("Chofer Desvío", "desvio@glassflow.com", "+593977777777");
        PedidoResponse pedido = logisticaService.crearPedido(CrearPedidoRequest.builder()
                .cliente("Taller Carcelén")
                .direccionTexto("Av. Amazonas y Orellana, Quito")
                .latitud(-0.1807)
                .longitud(-78.4678)
                .build());

        // 2. Asignar ruta
        DespachoResponse despacho = logisticaService.asignarDespacho(AsignarDespachoRequest.builder()
                .pedidoId(pedido.getId())
                .choferId(chofer.getId())
                .build());

        // 3. Chofer reporta entrega en Cumbayá (-0.2035, -78.4350), a más de 4000 metros del destino
        CerrarEntregaRequest cierreConDesvio = CerrarEntregaRequest.builder()
                .fotoPodUrl("https://storage.glassflow.com/pod/foto_desvio.jpg")
                .firmaUrl("data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==")
                .latitud(-0.2035)
                .longitud(-78.4350)
                .comentarios("Entrega realizada fuera de zona acordada.")
                .build();

        DespachoResponse cerrado = logisticaService.cerrarEntrega(despacho.getId(), cierreConDesvio);

        // CP-LOG-02: Debe marcar alerta de desviación geográfica (> 500m)
        assertTrue(cerrado.getAlertaDesviacion(), "Debe activar alerta de desviación al superar los 500 metros.");
        assertTrue(cerrado.getDesviacionMetros() > 500.0, "La distancia registrada debe ser superior a 500 metros.");
    }

    @Test
    @DisplayName("CP-LOG-01 / RF-03: Rechazo de cierre si falta evidencia fotográfica o firma digital")
    void testCierreEntregaSinEvidenciaFalla_CP_LOG_01() {
        ChoferResponse chofer = logisticaService.crearChofer("Chofer Sin Evidencia", "sinevidencia@glassflow.com", null);
        PedidoResponse pedido = logisticaService.crearPedido(CrearPedidoRequest.builder()
                .cliente("Cliente Test")
                .direccionTexto("Calle Falsa 123")
                .latitud(-0.1800)
                .longitud(-78.4600)
                .build());

        DespachoResponse despacho = logisticaService.asignarDespacho(AsignarDespachoRequest.builder()
                .pedidoId(pedido.getId())
                .choferId(chofer.getId())
                .build());

        // Intento 1: Sin foto
        CerrarEntregaRequest sinFoto = CerrarEntregaRequest.builder()
                .fotoPodUrl("")
                .firmaUrl("firma_ok")
                .latitud(-0.1800)
                .longitud(-78.4600)
                .build();

        assertThrows(IllegalArgumentException.class, () ->
                logisticaService.cerrarEntrega(despacho.getId(), sinFoto)
        );

        // Intento 2: Sin firma
        CerrarEntregaRequest sinFirma = CerrarEntregaRequest.builder()
                .fotoPodUrl("foto_ok")
                .firmaUrl("")
                .latitud(-0.1800)
                .longitud(-78.4600)
                .build();

        assertThrows(IllegalArgumentException.class, () ->
                logisticaService.cerrarEntrega(despacho.getId(), sinFirma)
        );

        // Intento 3: Sin GPS
        CerrarEntregaRequest sinGps = CerrarEntregaRequest.builder()
                .fotoPodUrl("foto_ok")
                .firmaUrl("firma_ok")
                .latitud(null)
                .longitud(null)
                .build();

        assertThrows(IllegalArgumentException.class, () ->
                logisticaService.cerrarEntrega(despacho.getId(), sinGps)
        );
    }
}
