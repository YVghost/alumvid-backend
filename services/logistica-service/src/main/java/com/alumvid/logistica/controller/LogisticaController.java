package com.alumvid.logistica.controller;

import com.alumvid.logistica.dto.*;
import com.alumvid.logistica.security.Sesion;
import com.alumvid.logistica.service.LogisticaService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Rutas de reparto, paradas, choferes en ruta, GPS y prueba de entrega.
 * La seguridad por rol está en LogisticaSecurity; aquí se valida la propiedad
 * (un chofer solo opera sus rutas).
 */
@RestController
@RequestMapping("/api/v1/logistica")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class LogisticaController {

    private final LogisticaService logisticaService;
    private final SimpMessagingTemplate messagingTemplate;
    private final Map<String, TelemetriaGpsPayload> ultimasUbicaciones = new ConcurrentHashMap<>();

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> healthCheck() {
        return ResponseEntity.ok(Map.of("status", "UP", "service", "logistica-service"));
    }

    // ---------------------------------------------------------------- choferes

    @GetMapping("/choferes")
    public List<ChoferResponse> listarChoferes() {
        return logisticaService.listarChoferes();
    }

    @GetMapping("/choferes/{idChofer}/rutas")
    public List<RutaResponse> listarRutasPorChofer(@PathVariable UUID idChofer) {
        Sesion.exigirPropietario(idChofer);
        return logisticaService.listarRutasPorChofer(idChofer);
    }

    @GetMapping("/choferes/{idChofer}/despachos-hoy")
    public List<DespachoResponse> listarDespachosHoyChofer(@PathVariable UUID idChofer) {
        Sesion.exigirPropietario(idChofer);
        return logisticaService.listarDespachosHoyChofer(idChofer);
    }

    // ---------------------------------------------------------------- rutas (planificación)

    @GetMapping("/rutas")
    public List<RutaResponse> listarRutas() {
        return logisticaService.listarRutas();
    }

    @GetMapping("/rutas/{id}")
    public RutaResponse obtenerRutaPorId(@PathVariable UUID id) {
        Sesion.exigirPropietario(logisticaService.choferDeRuta(id));
        return logisticaService.obtenerRutaPorId(id);
    }

    /** Crea una ruta con un chofer disponible y, opcionalmente, sus primeros pedidos. */
    @PostMapping("/rutas")
    public ResponseEntity<RutaResponse> crearRuta(@Valid @RequestBody CrearRutaSimpleRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(logisticaService.crearRuta(request));
    }

    @PostMapping("/rutas/{id}/pedidos")
    public RutaResponse agregarPedidos(@PathVariable UUID id, @Valid @RequestBody AgregarPedidosRequest request) {
        return logisticaService.agregarPedidos(id, request);
    }

    @PutMapping("/rutas/{rutaId}/destinos/{despachoId}/carga")
    public RutaResponse modificarCarga(@PathVariable UUID rutaId, @PathVariable UUID despachoId,
                                       @Valid @RequestBody ModificarCargaRequest request) {
        return logisticaService.modificarCarga(rutaId, despachoId, request);
    }

    @DeleteMapping("/rutas/{rutaId}/destinos/{despachoId}")
    public RutaResponse eliminarDestinoRuta(@PathVariable UUID rutaId, @PathVariable UUID despachoId) {
        return logisticaService.eliminarDestinoRuta(rutaId, despachoId);
    }

    @PutMapping("/rutas/{id}/chofer")
    public RutaResponse asignarChoferRuta(@PathVariable UUID id, @Valid @RequestBody AsignarChoferRutaRequest request) {
        return logisticaService.asignarChoferRuta(id, request.getChoferId());
    }

    @PostMapping("/rutas/{id}/iniciar")
    public RutaResponse iniciarRuta(@PathVariable UUID id) {
        return logisticaService.aceptarEIniciarRutaConsolidada(id);
    }

    @PostMapping("/rutas/{id}/cancelar")
    public RutaResponse cancelarRutaConsolidada(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> payload) {
        return logisticaService.cancelarRutaConsolidada(id, payload != null ? payload.get("motivo") : null);
    }

    @PostMapping("/rutas/{id}/completar")
    public RutaResponse completarRutaConsolidada(@PathVariable UUID id) {
        return logisticaService.completarRutaConsolidada(id);
    }

    @DeleteMapping("/rutas/{id}")
    public Map<String, String> eliminarRuta(@PathVariable UUID id) {
        logisticaService.eliminarRuta(id);
        return Map.of("mensaje", "Ruta eliminada");
    }

    @PostMapping("/rutas/{id}/optimizar-chofer")
    public RutaResponse optimizarRutaChofer(@PathVariable UUID id,
                                            @RequestParam(required = false) Double latitud,
                                            @RequestParam(required = false) Double longitud) {
        Sesion.exigirPropietario(logisticaService.choferDeRuta(id));
        return logisticaService.optimizarRutaPorChofer(id, latitud, longitud);
    }

    // ---------------------------------------------------------------- paradas (chofer en ruta)

    @GetMapping("/despachos")
    public List<DespachoResponse> listarDespachos() {
        return logisticaService.listarDespachos();
    }

    @PostMapping("/despachos/{id}/aceptar-inicio")
    public DespachoResponse aceptarEIniciarRuta(@PathVariable UUID id) {
        Sesion.exigirPropietario(logisticaService.choferDeDespacho(id));
        return logisticaService.aceptarEIniciarRuta(id);
    }

    @PostMapping("/despachos/{id}/cancelar")
    public DespachoResponse cancelarParada(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> payload) {
        Sesion.exigirPropietario(logisticaService.choferDeDespacho(id));
        return logisticaService.cancelarRuta(id, payload != null ? payload.get("motivo") : null);
    }

    @PostMapping("/despachos/{id}/reintentar")
    public DespachoResponse reintentarParada(@PathVariable UUID id) {
        Sesion.exigirPropietario(logisticaService.choferDeDespacho(id));
        return logisticaService.reintentarParada(id);
    }

    @PostMapping("/despachos/{id}/cerrar-entrega")
    public DespachoResponse cerrarEntrega(@PathVariable UUID id, @Valid @RequestBody CerrarEntregaRequest request) {
        Sesion.exigirPropietario(logisticaService.choferDeDespacho(id));
        return logisticaService.cerrarEntrega(id, request);
    }

    @GetMapping("/despachos/{id}/evidencia")
    public EvidenciaPodResponse obtenerEvidenciaPod(@PathVariable UUID id) {
        return logisticaService.obtenerEvidenciaPod(id);
    }

    // ---------------------------------------------------------------- telemetría

    @PostMapping("/telemetria")
    public Map<String, Object> recibirTelemetriaHttp(@RequestBody TelemetriaGpsPayload payload) {
        var actor = Sesion.actor();
        if (payload == null) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Ubicación vacía");
        if (!actor.admin()) {
            // Un chofer solo publica su propia ubicación.
            payload.setChoferId(actor.id());
            payload.setChoferNombre(actor.fullName());
        }
        if (payload.getTimestamp() == null) payload.setTimestamp(System.currentTimeMillis());
        if (payload.getChoferId() != null) ultimasUbicaciones.put(payload.getChoferId().toString(), payload);
        if (payload.getDespachoId() != null) {
            messagingTemplate.convertAndSend("/topic/despachos/" + payload.getDespachoId() + "/ubicacion", payload);
        }
        messagingTemplate.convertAndSend("/topic/choferes-activos", payload);
        return Map.of("status", "RECEIVED", "timestamp", System.currentTimeMillis());
    }

    @GetMapping("/telemetria/activa")
    public Collection<TelemetriaGpsPayload> obtenerTelemetriaActiva() {
        return ultimasUbicaciones.values();
    }

    @PostMapping("/notificaciones/sesion-revocada")
    public Map<String, Object> notificarSesionRevocada(@RequestBody(required = false) Map<String, String> body) {
        String userId = body != null ? body.get("userId") : null;
        if (userId != null && !userId.isBlank()) {
            messagingTemplate.convertAndSend("/topic/choferes/" + userId + "/sesion-revocada",
                    Map.of("tipo", "SESION_REVOCADA", "userId", userId, "mensaje", "Sesion revocada por el administrador"));
        }
        messagingTemplate.convertAndSend("/topic/sesiones-revocadas",
                Map.of("tipo", "SESION_REVOCADA", "userId", userId != null ? userId : ""));
        return Map.of("success", true);
    }
}
