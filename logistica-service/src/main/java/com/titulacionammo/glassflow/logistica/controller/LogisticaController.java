package com.titulacionammo.glassflow.logistica.controller;

import com.titulacionammo.glassflow.logistica.dto.*;
import com.titulacionammo.glassflow.logistica.service.LogisticaService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Controlador REST para gestion de logistica, hojas de ruta y evidencia de entrega e-PoD.
 */
@RestController
@RequestMapping("/api/v1/logistica")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class LogisticaController {

    private final LogisticaService logisticaService;

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> healthCheck() {
        return ResponseEntity.ok(Map.of("status", "UP", "service", "logistica-service"));
    }

    @PostMapping("/pedidos")
    public ResponseEntity<PedidoResponse> crearPedido(@Valid @RequestBody CrearPedidoRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(logisticaService.crearPedido(request));
    }

    @GetMapping("/pedidos")
    public ResponseEntity<List<PedidoResponse>> listarPedidos() {
        return ResponseEntity.ok(logisticaService.listarPedidos());
    }

    @GetMapping("/pedidos/pendientes")
    public ResponseEntity<List<PedidoResponse>> listarPedidosPendientes() {
        return ResponseEntity.ok(logisticaService.listarPedidosPendientes());
    }

    @PostMapping("/choferes/sincronizar")
    public ResponseEntity<ChoferResponse> sincronizarChofer(@Valid @RequestBody SincronizarChoferRequest request) {
        return ResponseEntity.ok(logisticaService.sincronizarOCrearChofer(request));
    }

    @GetMapping("/choferes")
    public ResponseEntity<List<ChoferResponse>> listarChoferes() {
        return ResponseEntity.ok(logisticaService.listarChoferes());
    }

    @PostMapping("/despachos/asignar")
    public ResponseEntity<DespachoResponse> asignarDespacho(@Valid @RequestBody AsignarDespachoRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(logisticaService.asignarDespacho(request));
    }

    @PostMapping("/despachos/{id}/aceptar-inicio")
    public ResponseEntity<DespachoResponse> aceptarEIniciarRuta(@PathVariable UUID id) {
        return ResponseEntity.ok(logisticaService.aceptarEIniciarRuta(id));
    }

    @PostMapping("/despachos/{id}/cancelar")
    public ResponseEntity<DespachoResponse> cancelarRuta(
            @PathVariable UUID id,
            @RequestBody(required = false) Map<String, String> payload) {
        String motivo = payload != null ? payload.get("motivo") : null;
        return ResponseEntity.ok(logisticaService.cancelarRuta(id, motivo));
    }

    @PostMapping("/despachos/{id}/cerrar-entrega")
    public ResponseEntity<DespachoResponse> cerrarEntrega(
            @PathVariable UUID id,
            @Valid @RequestBody CerrarEntregaRequest request) {
        return ResponseEntity.ok(logisticaService.cerrarEntrega(id, request));
    }

    @GetMapping("/despachos")
    public ResponseEntity<List<DespachoResponse>> listarDespachos() {
        return ResponseEntity.ok(logisticaService.listarDespachos());
    }

    @GetMapping("/choferes/{idChofer}/despachos-hoy")
    public ResponseEntity<List<DespachoResponse>> listarDespachosHoyChofer(@PathVariable UUID idChofer) {
        return ResponseEntity.ok(logisticaService.listarDespachosHoyChofer(idChofer));
    }

    @GetMapping("/despachos/{id}/evidencia")
    public ResponseEntity<EvidenciaPodResponse> obtenerEvidenciaPod(@PathVariable UUID id) {
        return ResponseEntity.ok(logisticaService.obtenerEvidenciaPod(id));
    }

    @PostMapping("/rutas")
    public ResponseEntity<RutaResponse> crearRutaConsolidada(@Valid @RequestBody CrearRutaConsolidadaRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(logisticaService.crearRutaConsolidada(request));
    }

    @GetMapping("/rutas")
    public ResponseEntity<List<RutaResponse>> listarRutas() {
        return ResponseEntity.ok(logisticaService.listarRutas());
    }

    @GetMapping("/rutas/{id}")
    public ResponseEntity<RutaResponse> obtenerRutaPorId(@PathVariable UUID id) {
        return ResponseEntity.ok(logisticaService.obtenerRutaPorId(id));
    }

    @GetMapping("/choferes/{idChofer}/rutas")
    public ResponseEntity<List<RutaResponse>> listarRutasPorChofer(@PathVariable UUID idChofer) {
        return ResponseEntity.ok(logisticaService.listarRutasPorChofer(idChofer));
    }

    @PostMapping("/rutas/{id}/iniciar")
    public ResponseEntity<RutaResponse> aceptarEIniciarRutaConsolidada(@PathVariable UUID id) {
        return ResponseEntity.ok(logisticaService.aceptarEIniciarRutaConsolidada(id));
    }

    @PostMapping("/rutas/{id}/cancelar")
    public ResponseEntity<RutaResponse> cancelarRutaConsolidada(
            @PathVariable UUID id,
            @RequestBody(required = false) Map<String, String> payload) {
        String motivo = payload != null ? payload.get("motivo") : null;
        return ResponseEntity.ok(logisticaService.cancelarRutaConsolidada(id, motivo));
    }
}
