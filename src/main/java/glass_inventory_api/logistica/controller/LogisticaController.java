package glass_inventory_api.logistica.controller;

import glass_inventory_api.logistica.dto.*;
import glass_inventory_api.logistica.service.LogisticaService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/logistica")
@CrossOrigin(origins = "*") // Permite el consumo desde portal React y app Flutter
@RequiredArgsConstructor
public class LogisticaController {

    private final LogisticaService logisticaService;

    // --- PEDIDOS ---

    @PostMapping("/pedidos")
    public ResponseEntity<PedidoResponse> crearPedido(@Valid @RequestBody CrearPedidoRequest request) {
        PedidoResponse response = logisticaService.crearPedido(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/pedidos")
    public ResponseEntity<List<PedidoResponse>> listarPedidos() {
        return ResponseEntity.ok(logisticaService.listarPedidos());
    }

    @GetMapping("/pedidos/pendientes")
    public ResponseEntity<List<PedidoResponse>> listarPedidosPendientes() {
        return ResponseEntity.ok(logisticaService.listarPedidosPendientes());
    }

    // --- CHOFERES ---

    @GetMapping("/choferes")
    public ResponseEntity<List<ChoferResponse>> listarChoferes() {
        return ResponseEntity.ok(logisticaService.listarChoferes());
    }

    @PostMapping("/choferes")
    public ResponseEntity<ChoferResponse> crearChofer(
            @RequestParam String nombre,
            @RequestParam String email,
            @RequestParam(required = false) String telefono) {
        ChoferResponse response = logisticaService.crearChofer(nombre, email, telefono);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/choferes/{idChofer}/despachos-hoy")
    public ResponseEntity<List<DespachoResponse>> listarDespachosPorChofer(@PathVariable UUID idChofer) {
        return ResponseEntity.ok(logisticaService.listarDespachosPorChofer(idChofer));
    }

    // --- DESPACHOS Y RUTAS (HU-04, HU-05, HU-06) ---

    @PostMapping("/despachos/asignar")
    public ResponseEntity<DespachoResponse> asignarDespacho(@Valid @RequestBody AsignarDespachoRequest request) {
        DespachoResponse response = logisticaService.asignarDespacho(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/despachos")
    public ResponseEntity<List<DespachoResponse>> listarTodosDespachos() {
        return ResponseEntity.ok(logisticaService.listarTodosDespachos());
    }

    @PatchMapping("/despachos/{id}/iniciar")
    public ResponseEntity<DespachoResponse> iniciarRuta(@PathVariable UUID id) {
        return ResponseEntity.ok(logisticaService.iniciarRuta(id));
    }

    @PostMapping("/despachos/{id}/cerrar-entrega")
    public ResponseEntity<DespachoResponse> cerrarEntrega(
            @PathVariable UUID id,
            @Valid @RequestBody CerrarEntregaRequest request) {
        DespachoResponse response = logisticaService.cerrarEntrega(id, request);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/despachos/{id}/evidencia")
    public ResponseEntity<EvidenciaPodResponse> obtenerEvidencia(@PathVariable UUID id) {
        return ResponseEntity.ok(logisticaService.obtenerEvidencia(id));
    }
}
