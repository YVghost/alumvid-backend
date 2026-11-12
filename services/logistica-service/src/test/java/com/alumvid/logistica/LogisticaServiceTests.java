package com.alumvid.logistica;

import com.alumvid.logistica.dto.CerrarEntregaRequest;
import com.alumvid.logistica.dto.CrearRutaSimpleRequest;
import com.alumvid.logistica.model.*;
import com.alumvid.logistica.repository.ChoferRepository;
import com.alumvid.logistica.repository.DespachoRepository;
import com.alumvid.logistica.repository.PedidoRepository;
import com.alumvid.logistica.repository.RutaRepository;
import com.alumvid.logistica.security.AuthClient;
import com.alumvid.logistica.service.*;
import com.alumvid.logistica.util.GeometryUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** Reglas de planificación y operación de rutas (sin base de datos). */
class LogisticaServiceTests {

    private final ChoferRepository choferes = mock(ChoferRepository.class);
    private final PedidoRepository destinos = mock(PedidoRepository.class);
    private final DespachoRepository despachos = mock(DespachoRepository.class);
    private final RutaRepository rutas = mock(RutaRepository.class);
    private final CommercialOrderBridge bridge = mock(CommercialOrderBridge.class);
    private final PedidosClient pedidos = mock(PedidosClient.class);
    private final AuthClient auth = mock(AuthClient.class);
    private LogisticaServiceImpl service;

    private final Chofer chofer = Chofer.builder().id(UUID.randomUUID()).nombre("Chofer Uno").email("c1@test").estadoDisponibilidad(EstadoChofer.DISPONIBLE).build();

    @BeforeEach
    void setUp() {
        service = new LogisticaServiceImpl(choferes, destinos, despachos, rutas, mock(SimpMessagingTemplate.class),
                mock(GoogleRoutesService.class), mock(JdbcTemplate.class), bridge, pedidos, auth, new ObjectMapper());
        var admin = new AuthClient.Identity(UUID.randomUUID(), "ADMIN", "Admin", Set.of("ADMINISTRADOR"), false, true, false);
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(admin, "Bearer test", List.of()));
        when(choferes.findById(chofer.getId())).thenReturn(Optional.of(chofer));
        when(choferes.findAll()).thenReturn(List.of(chofer));
        when(rutas.save(any())).thenAnswer(i -> i.getArgument(0));
        when(despachos.save(any())).thenAnswer(i -> i.getArgument(0));
        when(rutas.existsByCodigoRuta(any())).thenReturn(false);
    }

    @AfterEach
    void limpiar() {
        SecurityContextHolder.clearContext();
    }

    private void choferActivo() {
        when(auth.activeDrivers(any())).thenReturn(List.of(Map.of("id", chofer.getId().toString(), "fullName", chofer.getNombre(), "email", "c1@test", "active", true, "mustChangePassword", false)));
    }

    private Ruta ruta(EstadoRuta estado) {
        var r = Ruta.builder().id(UUID.randomUUID()).codigoRuta("R-1").chofer(chofer).estado(estado)
                .fechaCreacion(LocalDateTime.now()).paradas(new ArrayList<>()).build();
        when(rutas.findById(r.getId())).thenReturn(Optional.of(r));
        return r;
    }

    private Despacho parada(Ruta r, int orden, EstadoDespacho estado) {
        var destino = Pedido.builder().id(UUID.randomUUID()).cliente("Cliente").direccionTexto("Quito")
                .coordenadaDestino(GeometryUtil.crearPunto(-0.18, -78.46)).estado(EstadoPedido.PENDIENTE).build();
        var d = Despacho.builder().id(UUID.randomUUID()).ruta(r).ordenParada(orden).pedido(destino).chofer(chofer)
                .fechaAsignacion(LocalDateTime.now()).estado(estado).build();
        r.getParadas().add(d);
        when(despachos.findById(d.getId())).thenReturn(Optional.of(d));
        return d;
    }

    private static int status(Executable e) {
        return assertThrows(ResponseStatusException.class, e::run).getStatusCode().value();
    }

    @FunctionalInterface
    interface Executable { void run(); }

    @Test
    @DisplayName("No se cambia el chofer de una ruta en curso")
    void choferNoCambiaEnCurso() {
        var r = ruta(EstadoRuta.EN_CURSO);
        assertEquals(409, status(() -> service.asignarChoferRuta(r.getId(), chofer.getId())));
    }

    @Test
    @DisplayName("Un chofer en ruta no recibe una ruta nueva")
    void choferEnRutaNoSeAsigna() {
        choferActivo();
        var otra = Ruta.builder().id(UUID.randomUUID()).estado(EstadoRuta.EN_CURSO).paradas(new ArrayList<>()).build();
        parada(otra, 1, EstadoDespacho.PENDIENTE);
        when(rutas.findByChoferIdAndEstadoIn(eq(chofer.getId()), anyList())).thenReturn(List.of(otra));
        var e = assertThrows(ResponseStatusException.class, () -> service.crearRuta(new CrearRutaSimpleRequest("R-2", chofer.getId(), null, null)));
        assertEquals(HttpStatus.CONFLICT, e.getStatusCode());
        assertTrue(e.getReason().contains("está en ruta"));
    }

    @Test
    @DisplayName("Un chofer inactivo (o con clave temporal) no se asigna")
    void choferInactivoNoSeAsigna() {
        when(auth.activeDrivers(any())).thenReturn(List.of());
        var e = assertThrows(ResponseStatusException.class, () -> service.crearRuta(new CrearRutaSimpleRequest("R-3", chofer.getId(), null, null)));
        assertTrue(e.getReason().contains("inactivo"));
    }

    @Test
    @DisplayName("Un chofer disponible recibe la ruta nueva")
    void choferDisponibleSeAsigna() {
        choferActivo();
        var creada = service.crearRuta(new CrearRutaSimpleRequest("R-4", chofer.getId(), "Norte", null));
        assertEquals(EstadoRuta.PENDIENTE, creada.getEstado());
        assertEquals(chofer.getId(), creada.getChoferId());
    }

    @Test
    @DisplayName("Quitar una parada de una ruta pendiente devuelve el material a bodega")
    void quitarParadaAnulaEnvio() {
        var r = ruta(EstadoRuta.PENDIENTE);
        var d = parada(r, 1, EstadoDespacho.PENDIENTE);
        d.setEnvioComercialId(UUID.randomUUID());
        service.eliminarDestinoRuta(r.getId(), d.getId());
        verify(pedidos).anular(eq(d.getEnvioComercialId()), anyString());
        assertTrue(r.getParadas().isEmpty());
    }

    @Test
    @DisplayName("No se agregan pedidos a una ruta en curso")
    void noAgregarEnCurso() {
        var r = ruta(EstadoRuta.EN_CURSO);
        assertEquals(409, status(() -> service.agregarPedidos(r.getId(), new com.alumvid.logistica.dto.AgregarPedidosRequest(List.of()))));
    }

    @Test
    @DisplayName("La entrega exige foto, firma y GPS")
    void entregaExigeEvidencia() {
        var r = ruta(EstadoRuta.EN_CURSO);
        var d = parada(r, 1, EstadoDespacho.EN_CURSO);
        var sinFoto = CerrarEntregaRequest.builder().firmaUrl("data:x").latitud(-0.18).longitud(-78.46).build();
        assertEquals(400, status(() -> service.cerrarEntrega(d.getId(), sinFoto)));
        verify(bridge, never()).delivered(any());
    }

    @Test
    @DisplayName("La ruta se cierra sola al terminar sus paradas y lo no entregado vuelve a bodega")
    void cierreAutomatico() {
        var r = ruta(EstadoRuta.EN_CURSO);
        var entregada = parada(r, 1, EstadoDespacho.ENTREGADO);
        var ultima = parada(r, 2, EstadoDespacho.EN_CURSO);
        service.cancelarRuta(ultima.getId(), "Cliente ausente");
        assertEquals(EstadoDespacho.CANCELADA, ultima.getEstado());
        assertEquals(EstadoRuta.COMPLETADA, r.getEstado());
        verify(bridge).cancelled(eq(ultima.getId()), anyString());
        verify(bridge, never()).cancelled(eq(entregada.getId()), anyString());
    }

    @Test
    @DisplayName("Una parada no entregada puede reintentarse mientras la ruta sigue en curso")
    void reintentoMientrasEnCurso() {
        var r = ruta(EstadoRuta.EN_CURSO);
        parada(r, 1, EstadoDespacho.PENDIENTE);
        var fallida = parada(r, 2, EstadoDespacho.CANCELADA);
        when(bridge.estados(any())).thenReturn(Map.of(fallida.getId(), "EN_REPARTO"));
        service.reintentarParada(fallida.getId());
        assertEquals(EstadoDespacho.PENDIENTE, fallida.getEstado());
    }
}
