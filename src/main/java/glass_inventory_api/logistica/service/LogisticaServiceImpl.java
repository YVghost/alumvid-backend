package glass_inventory_api.logistica.service;

import glass_inventory_api.logistica.dto.*;
import glass_inventory_api.logistica.model.*;
import glass_inventory_api.logistica.repository.ChoferRepository;
import glass_inventory_api.logistica.repository.DespachoRepository;
import glass_inventory_api.logistica.repository.PedidoRepository;
import glass_inventory_api.logistica.util.GeoDistanceCalculator;
import glass_inventory_api.logistica.util.GeometryUtil;
import jakarta.persistence.EntityNotFoundException;
import lombok.RequiredArgsConstructor;
import org.locationtech.jts.geom.Point;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class LogisticaServiceImpl implements LogisticaService {

    private static final double UMBRAL_DESVIACION_METROS = 500.0;

    private final PedidoRepository pedidoRepository;
    private final ChoferRepository choferRepository;
    private final DespachoRepository despachoRepository;

    @Override
    @Transactional
    public PedidoResponse crearPedido(CrearPedidoRequest request) {
        Point destino = GeometryUtil.createPoint(request.getLatitud(), request.getLongitud());

        Pedido pedido = Pedido.builder()
                .cliente(request.getCliente().trim())
                .direccionTexto(request.getDireccionTexto().trim())
                .coordenadaDestino(destino)
                .estado(EstadoPedido.PENDIENTE)
                .build();

        Pedido guardado = pedidoRepository.save(pedido);
        return PedidoResponse.fromEntity(guardado);
    }

    @Override
    @Transactional(readOnly = true)
    public List<PedidoResponse> listarPedidos() {
        return pedidoRepository.findAllByOrderByFechaSolicitudDesc()
                .stream()
                .map(PedidoResponse::fromEntity)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public List<PedidoResponse> listarPedidosPendientes() {
        return pedidoRepository.findByEstado(EstadoPedido.PENDIENTE)
                .stream()
                .map(PedidoResponse::fromEntity)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public ChoferResponse crearChofer(String nombre, String email, String telefono) {
        Chofer chofer = Chofer.builder()
                .nombre(nombre.trim())
                .email(email.trim().toLowerCase())
                .telefono(telefono != null ? telefono.trim() : null)
                .estadoDisponibilidad(EstadoChofer.DISPONIBLE)
                .build();

        Chofer guardado = choferRepository.save(chofer);
        return ChoferResponse.fromEntity(guardado);
    }

    @Override
    @Transactional(readOnly = true)
    public List<ChoferResponse> listarChoferes() {
        return choferRepository.findAll()
                .stream()
                .map(ChoferResponse::fromEntity)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public DespachoResponse asignarDespacho(AsignarDespachoRequest request) {
        Pedido pedido = pedidoRepository.findById(request.getPedidoId())
                .orElseThrow(() -> new EntityNotFoundException("Pedido no encontrado con ID: " + request.getPedidoId()));

        if (pedido.getEstado() != EstadoPedido.PENDIENTE) {
            throw new IllegalStateException("El pedido con ID " + pedido.getId() + " ya no está pendiente (estado actual: " + pedido.getEstado() + ")");
        }

        Chofer chofer = choferRepository.findById(request.getChoferId())
                .orElseThrow(() -> new EntityNotFoundException("Chofer no encontrado con ID: " + request.getChoferId()));

        // Verificar si ya existe despacho para este pedido
        if (despachoRepository.findByPedidoId(pedido.getId()).isPresent()) {
            throw new IllegalStateException("El pedido ya tiene un despacho asignado.");
        }

        // Crear despacho
        Despacho despacho = Despacho.builder()
                .pedido(pedido)
                .chofer(chofer)
                .fechaAsignacion(LocalDateTime.now())
                .estado(EstadoDespacho.PENDIENTE)
                .alertaDesviacion(false)
                .build();

        // Actualizar estados
        pedido.setEstado(EstadoPedido.EN_RUTA);
        chofer.setEstadoDisponibilidad(EstadoChofer.EN_RUTA);

        pedidoRepository.save(pedido);
        choferRepository.save(chofer);
        Despacho guardado = despachoRepository.save(despacho);

        return DespachoResponse.fromEntity(guardado);
    }

    @Override
    @Transactional(readOnly = true)
    public List<DespachoResponse> listarTodosDespachos() {
        return despachoRepository.findAllByOrderByFechaAsignacionDesc()
                .stream()
                .map(DespachoResponse::fromEntity)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public List<DespachoResponse> listarDespachosPorChofer(UUID choferId) {
        return despachoRepository.findByChoferIdOrderByFechaAsignacionDesc(choferId)
                .stream()
                .map(DespachoResponse::fromEntity)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public DespachoResponse iniciarRuta(UUID despachoId) {
        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new EntityNotFoundException("Despacho no encontrado con ID: " + despachoId));

        if (despacho.getEstado() == EstadoDespacho.ENTREGADO) {
            throw new IllegalStateException("El despacho ya fue completado y entregado previamente.");
        }

        despacho.setEstado(EstadoDespacho.EN_RUTA);
        despacho.getChofer().setEstadoDisponibilidad(EstadoChofer.EN_RUTA);

        Despacho guardado = despachoRepository.save(despacho);
        return DespachoResponse.fromEntity(guardado);
    }

    @Override
    @Transactional
    public DespachoResponse cerrarEntrega(UUID despachoId, CerrarEntregaRequest request) {
        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new EntityNotFoundException("Despacho no encontrado con ID: " + despachoId));

        if (despacho.getEstado() == EstadoDespacho.ENTREGADO) {
            throw new IllegalStateException("Este despacho ya ha sido marcado como entregado.");
        }

        // Validación estricta de evidencia PoD (RF-03, HU-05)
        if (request.getFotoPodUrl() == null || request.getFotoPodUrl().trim().isEmpty()) {
            throw new IllegalArgumentException("La fotografía de evidencia (Proof of Delivery) es obligatoria.");
        }
        if (request.getFirmaUrl() == null || request.getFirmaUrl().trim().isEmpty()) {
            throw new IllegalArgumentException("La firma digital del cliente es obligatoria.");
        }

        // Validación estricta de telemetría GPS (RF-04, HU-06, CP-LOG-01)
        if (request.getLatitud() == null || request.getLongitud() == null) {
            throw new IllegalArgumentException("Las coordenadas GPS de entrega son obligatorias. Active el sensor de ubicación.");
        }

        Point coordenadaEntrega = GeometryUtil.createPoint(request.getLatitud(), request.getLongitud());
        despacho.setCoordenadaEntrega(coordenadaEntrega);

        // Auditoría espacial y geofencing (CP-LOG-02)
        Point destinoCliente = despacho.getPedido().getCoordenadaDestino();
        double distanciaMetros = GeoDistanceCalculator.calcularDistanciaPuntos(coordenadaEntrega, destinoCliente);

        boolean alertaDesviacion = distanciaMetros > UMBRAL_DESVIACION_METROS;

        despacho.setDesviacionMetros(distanciaMetros);
        despacho.setAlertaDesviacion(alertaDesviacion);
        despacho.setFotoPodUrl(request.getFotoPodUrl().trim());
        despacho.setFirmaUrl(request.getFirmaUrl().trim());
        despacho.setFechaEntrega(LocalDateTime.now());
        despacho.setEstado(EstadoDespacho.ENTREGADO);
        if (request.getComentarios() != null) {
            despacho.setComentarios(request.getComentarios().trim());
        }

        // Actualizar pedido a ENTREGADO
        despacho.getPedido().setEstado(EstadoPedido.ENTREGADO);

        // Si el chofer ya no tiene más entregas activas, volver su disponibilidad a DISPONIBLE
        long despachosPendientes = despachoRepository.findByChoferIdAndEstado(despacho.getChofer().getId(), EstadoDespacho.EN_RUTA)
                .stream()
                .filter(d -> !d.getId().equals(despachoId))
                .count();

        if (despachosPendientes == 0) {
            despacho.getChofer().setEstadoDisponibilidad(EstadoChofer.DISPONIBLE);
        }

        Despacho guardado = despachoRepository.save(despacho);
        return DespachoResponse.fromEntity(guardado);
    }

    @Override
    @Transactional(readOnly = true)
    public EvidenciaPodResponse obtenerEvidencia(UUID despachoId) {
        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new EntityNotFoundException("Despacho no encontrado con ID: " + despachoId));

        if (despacho.getEstado() != EstadoDespacho.ENTREGADO) {
            throw new IllegalStateException("El despacho aún no ha sido entregado, por lo que no cuenta con evidencia completa.");
        }

        return EvidenciaPodResponse.fromEntity(despacho);
    }
}
