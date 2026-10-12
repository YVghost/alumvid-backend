package com.alumvid.logistica.service;

import com.alumvid.logistica.dto.*;
import com.alumvid.logistica.model.*;
import com.alumvid.logistica.repository.ChoferRepository;
import com.alumvid.logistica.repository.DespachoRepository;
import com.alumvid.logistica.repository.PedidoRepository;
import com.alumvid.logistica.repository.RutaRepository;
import com.alumvid.logistica.util.GeoDistanceCalculator;
import com.alumvid.logistica.util.GeometryUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.locationtech.jts.geom.Point;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Implementacion del servicio de logistica con soporte espacial PostGIS,
 * rutas consolidadas multi-parada y WebSockets en tiempo real.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class LogisticaServiceImpl implements LogisticaService {

    private static final double UMBRAL_ALERTA_DESVIACION_METROS = 150.0;

    private final ChoferRepository choferRepository;
    private final PedidoRepository pedidoRepository;
    private final DespachoRepository despachoRepository;
    private final RutaRepository rutaRepository;
    private final SimpMessagingTemplate messagingTemplate;

    @Override
    @Transactional
    public PedidoResponse crearPedido(CrearPedidoRequest request) {
        Point puntoDestino = GeometryUtil.crearPunto(request.getLatitud(), request.getLongitud());

        Pedido pedido = Pedido.builder()
                .cliente(request.getCliente().trim())
                .direccionTexto(request.getDireccionTexto().trim())
                .coordenadaDestino(puntoDestino)
                .estado(EstadoPedido.PENDIENTE)
                .build();

        Pedido guardado = pedidoRepository.save(pedido);
        log.info("Pedido registrado: {} para cliente: {}", guardado.getId(), guardado.getCliente());

        notificarActualizacionTablero();
        return mapearAPedidoResponse(guardado);
    }

    @Override
    @Transactional(readOnly = true)
    public List<PedidoResponse> listarPedidos() {
        return pedidoRepository.findAllByOrderByFechaSolicitudDesc().stream()
                .map(this::mapearAPedidoResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public List<PedidoResponse> listarPedidosPendientes() {
        return pedidoRepository.findByEstado(EstadoPedido.PENDIENTE).stream()
                .map(this::mapearAPedidoResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public ChoferResponse sincronizarOCrearChofer(SincronizarChoferRequest request) {
        Chofer chofer = choferRepository.findById(request.getId())
                .orElseGet(() -> Chofer.builder()
                        .id(request.getId())
                        .email(request.getEmail().toLowerCase().trim())
                        .build());

        chofer.setNombre(request.getNombre().trim());
        chofer.setEmail(request.getEmail().toLowerCase().trim());
        chofer.setTelefono(request.getTelefono() != null ? request.getTelefono().trim() : null);

        Chofer guardado = choferRepository.save(chofer);
        log.info("Perfil de chofer sincronizado: {} ({})", guardado.getNombre(), guardado.getId());
        return mapearAChoferResponse(guardado);
    }

    @Override
    @Transactional(readOnly = true)
    public List<ChoferResponse> listarChoferes() {
        return choferRepository.findAll().stream()
                .map(this::mapearAChoferResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public DespachoResponse asignarDespacho(AsignarDespachoRequest request) {
        Pedido pedido = pedidoRepository.findById(request.getPedidoId())
                .orElseThrow(() -> new IllegalArgumentException("Pedido no encontrado con ID: " + request.getPedidoId()));

        Chofer chofer = choferRepository.findById(request.getChoferId())
                .orElseThrow(() -> new IllegalArgumentException("Chofer no encontrado con ID: " + request.getChoferId()));

        if (pedido.getEstado() != EstadoPedido.PENDIENTE) {
            throw new IllegalStateException("El pedido ya se encuentra asignado o en proceso de despacho.");
        }

        // Crear una ruta consolidada unitaria bajo el nuevo modelo
        String codigoRuta = "RUTA-" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));
        Ruta ruta = Ruta.builder()
                .codigoRuta(codigoRuta)
                .chofer(chofer)
                .estado(EstadoRuta.PENDIENTE)
                .fechaCreacion(LocalDateTime.now())
                .build();
        Ruta rutaGuardada = rutaRepository.save(ruta);

        Despacho despacho = Despacho.builder()
                .ruta(rutaGuardada)
                .ordenParada(1)
                .pedido(pedido)
                .chofer(chofer)
                .fechaAsignacion(LocalDateTime.now())
                .estado(EstadoDespacho.PENDIENTE)
                .build();

        Despacho guardado = despachoRepository.save(despacho);
        rutaGuardada.getParadas().add(guardado);
        log.info("Ruta unitaria creada. Despacho: {} asignado a chofer: {}", guardado.getId(), chofer.getNombre());

        DespachoResponse response = mapearADespachoResponse(guardado);

        messagingTemplate.convertAndSend("/topic/choferes/" + chofer.getId() + "/rutas-asignadas", response);
        notificarActualizacionTablero();

        return response;
    }

    // Coordenadas base de la Central de Operaciones y Bodega AlumVid en Quito (Av. Amazonas y Orellana)
    private static final double LAT_BODEGA_QUITO = -0.1807;
    private static final double LON_BODEGA_QUITO = -78.4678;

    @Override
    @Transactional
    public RutaResponse crearRutaConsolidada(CrearRutaConsolidadaRequest request) {
        Chofer chofer = choferRepository.findById(request.getChoferId())
                .orElseThrow(() -> new IllegalArgumentException("Chofer no encontrado con ID: " + request.getChoferId()));

        List<Pedido> pedidos = pedidoRepository.findAllById(request.getPedidoIds());
        if (pedidos.isEmpty()) {
            throw new IllegalArgumentException("Debe seleccionar al menos un pedido valido.");
        }

        for (Pedido p : pedidos) {
            if (p.getEstado() != EstadoPedido.PENDIENTE) {
                throw new IllegalStateException("El pedido " + p.getId() + " ya no esta pendiente.");
            }
        }

        // Ordenamiento automatico de destinos por proximidad espacial (Nearest Neighbor TSP)
        List<Pedido> pedidosOrdenados = ordenarPedidosPorProximidad(pedidos, LAT_BODEGA_QUITO, LON_BODEGA_QUITO);

        String codigoRuta = "RUTA-" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));

        Ruta ruta = Ruta.builder()
                .codigoRuta(codigoRuta)
                .chofer(chofer)
                .estado(EstadoRuta.PENDIENTE)
                .fechaCreacion(LocalDateTime.now())
                .comentarios(request.getComentarios())
                .build();

        Ruta rutaGuardada = rutaRepository.save(ruta);

        List<Despacho> paradas = new ArrayList<>();
        int orden = 1;
        for (Pedido p : pedidosOrdenados) {
            Despacho d = Despacho.builder()
                    .ruta(rutaGuardada)
                    .ordenParada(orden++)
                    .pedido(p)
                    .chofer(chofer)
                    .fechaAsignacion(LocalDateTime.now())
                    .estado(EstadoDespacho.PENDIENTE)
                    .build();
            paradas.add(despachoRepository.save(d));
        }

        rutaGuardada.setParadas(paradas);

        RutaResponse response = mapearARutaResponse(rutaGuardada);
        messagingTemplate.convertAndSend("/topic/choferes/" + chofer.getId() + "/rutas-asignadas", response);
        notificarActualizacionTablero();

        return response;
    }

    @Override
    @Transactional
    public RutaResponse crearRutaMultiDestino(CrearRutaMultiDestinoRequest request) {
        Chofer chofer = choferRepository.findById(request.getChoferId())
                .orElseThrow(() -> new IllegalArgumentException("Chofer no encontrado con ID: " + request.getChoferId()));

        if (request.getDestinos() == null || request.getDestinos().isEmpty()) {
            throw new IllegalArgumentException("Debe ingresar al menos un destino para la ruta.");
        }

        // 1. Crear y persistir cada pedido de destino
        List<Pedido> pedidosCreados = new ArrayList<>();
        for (CrearRutaMultiDestinoRequest.DestinoItemRequest item : request.getDestinos()) {
            Point puntoDestino = GeometryUtil.crearPunto(item.getLatitudDestino(), item.getLongitudDestino());
            Pedido pedido = Pedido.builder()
                    .cliente(item.getCliente().trim())
                    .direccionTexto(item.getDireccionTexto().trim())
                    .coordenadaDestino(puntoDestino)
                    .estado(EstadoPedido.PENDIENTE)
                    .fechaSolicitud(LocalDateTime.now())
                    .build();
            pedidosCreados.add(pedidoRepository.save(pedido));
        }

        // 2. Ordenamiento automatico por proximidad desde el origen central
        List<Pedido> pedidosOrdenados = ordenarPedidosPorProximidad(pedidosCreados, LAT_BODEGA_QUITO, LON_BODEGA_QUITO);

        // 3. Crear la cabecera de la ruta consolidada
        String codigoBase = (request.getCodigoRuta() != null && !request.getCodigoRuta().trim().isEmpty())
                ? request.getCodigoRuta().trim()
                : "Ruta 1";
        String codigoRuta = codigoBase;
        if (rutaRepository.existsByCodigoRuta(codigoRuta)) {
            codigoRuta = codigoBase + " (" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss")) + ")";
        }

        Ruta ruta = Ruta.builder()
                .codigoRuta(codigoRuta)
                .chofer(chofer)
                .estado(EstadoRuta.PENDIENTE)
                .fechaCreacion(LocalDateTime.now())
                .comentarios(request.getComentarios())
                .build();

        Ruta rutaGuardada = rutaRepository.save(ruta);

        // 4. Crear los despachos con orden de parada secuencial optimizado
        List<Despacho> paradas = new ArrayList<>();
        int orden = 1;
        for (Pedido p : pedidosOrdenados) {
            Despacho d = Despacho.builder()
                    .ruta(rutaGuardada)
                    .ordenParada(orden++)
                    .pedido(p)
                    .chofer(chofer)
                    .fechaAsignacion(LocalDateTime.now())
                    .estado(EstadoDespacho.PENDIENTE)
                    .build();
            paradas.add(despachoRepository.save(d));
        }

        rutaGuardada.setParadas(paradas);

        RutaResponse response = mapearARutaResponse(rutaGuardada);
        messagingTemplate.convertAndSend("/topic/choferes/" + chofer.getId() + "/rutas-asignadas", response);
        notificarActualizacionTablero();

        return response;
    }

    /**
     * Algoritmo voraz de optimizacion de secuencia por proximidad espacial (Nearest Neighbor TSP).
     * Inicia en el punto de partida (Bodega Central) y selecciona iterativamente la parada mas cercana.
     */
    private List<Pedido> ordenarPedidosPorProximidad(List<Pedido> pedidos, double latOrigen, double lonOrigen) {
        if (pedidos == null || pedidos.size() <= 1) {
            return pedidos != null ? new ArrayList<>(pedidos) : new ArrayList<>();
        }

        List<Pedido> noVisitados = new ArrayList<>(pedidos);
        List<Pedido> rutaOptimizada = new ArrayList<>();

        double actualLat = latOrigen;
        double actualLon = lonOrigen;

        while (!noVisitados.isEmpty()) {
            Pedido masCercano = null;
            double menorDistancia = Double.MAX_VALUE;

            for (Pedido candidato : noVisitados) {
                Double candLat = GeometryUtil.extraerLatitud(candidato.getCoordenadaDestino());
                Double candLon = GeometryUtil.extraerLongitud(candidato.getCoordenadaDestino());

                if (candLat == null || candLon == null) {
                    continue;
                }

                double dist = GeometryUtil.calcularDistanciaMetros(actualLat, actualLon, candLat, candLon);
                if (dist < menorDistancia) {
                    menorDistancia = dist;
                    masCercano = candidato;
                }
            }

            if (masCercano == null) {
                masCercano = noVisitados.get(0);
            }

            rutaOptimizada.add(masCercano);
            noVisitados.remove(masCercano);

            Double sigLat = GeometryUtil.extraerLatitud(masCercano.getCoordenadaDestino());
            Double sigLon = GeometryUtil.extraerLongitud(masCercano.getCoordenadaDestino());
            if (sigLat != null && sigLon != null) {
                actualLat = sigLat;
                actualLon = sigLon;
            }
        }

        return rutaOptimizada;
    }

    @Override
    @Transactional(readOnly = true)
    public List<RutaResponse> listarRutas() {
        return rutaRepository.findAllByOrderByFechaCreacionDesc().stream()
                .map(this::mapearARutaResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public List<RutaResponse> listarRutasPorChofer(UUID choferId) {
        return rutaRepository.findByChoferIdOrderByFechaCreacionDesc(choferId).stream()
                .map(this::mapearARutaResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public RutaResponse obtenerRutaPorId(UUID rutaId) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));
        return mapearARutaResponse(ruta);
    }

    @Override
    @Transactional
    public RutaResponse aceptarEIniciarRutaConsolidada(UUID rutaId) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));

        if (ruta.getEstado() != EstadoRuta.PENDIENTE) {
            throw new IllegalStateException("La ruta no se encuentra en estado pendiente de aprobacion.");
        }

        ruta.setEstado(EstadoRuta.EN_CURSO);
        ruta.setFechaInicio(LocalDateTime.now());

        Chofer chofer = ruta.getChofer();
        chofer.setEstadoDisponibilidad(EstadoChofer.EN_RUTA);
        choferRepository.save(chofer);

        for (Despacho d : ruta.getParadas()) {
            if (d.getEstado() == EstadoDespacho.PENDIENTE) {
                d.setEstado(EstadoDespacho.EN_CURSO);
                d.setFechaInicioRuta(LocalDateTime.now());
                d.getPedido().setEstado(EstadoPedido.EN_RUTA);
                pedidoRepository.save(d.getPedido());
                despachoRepository.save(d);
            }
        }

        Ruta guardada = rutaRepository.save(ruta);
        messagingTemplate.convertAndSend("/topic/rutas/" + rutaId + "/estado",
                Map.of("rutaId", rutaId.toString(), "estado", "EN_CURSO", "mensaje", "Ruta consolidada iniciada"));
        notificarActualizacionTablero();

        return mapearARutaResponse(guardada);
    }

    @Override
    @Transactional
    public RutaResponse cancelarRutaConsolidada(UUID rutaId, String motivo) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));

        if (ruta.getEstado() == EstadoRuta.COMPLETADA) {
            throw new IllegalStateException("No se puede cancelar una ruta ya completada.");
        }

        ruta.setEstado(EstadoRuta.CANCELADA);
        ruta.setFechaFin(LocalDateTime.now());
        ruta.setComentarios(motivo != null ? "Cancelada: " + motivo : "Cancelada voluntariamente por el chofer.");

        Chofer chofer = ruta.getChofer();
        chofer.setEstadoDisponibilidad(EstadoChofer.DISPONIBLE);
        choferRepository.save(chofer);

        for (Despacho d : ruta.getParadas()) {
            if (d.getEstado() != EstadoDespacho.ENTREGADO) {
                d.setEstado(EstadoDespacho.CANCELADA);
                d.setComentarios(motivo != null ? motivo : "Ruta cancelada");
                d.getPedido().setEstado(EstadoPedido.CANCELADO);
                pedidoRepository.save(d.getPedido());
                despachoRepository.save(d);
            }
        }

        Ruta guardada = rutaRepository.save(ruta);
        messagingTemplate.convertAndSend("/topic/rutas/" + rutaId + "/estado",
                Map.of("rutaId", rutaId.toString(), "estado", "CANCELADA", "mensaje", "Ruta cancelada por chofer"));
        notificarActualizacionTablero();

        return mapearARutaResponse(guardada);
    }

    @Override
    @Transactional
    public DespachoResponse aceptarEIniciarRuta(UUID despachoId) {
        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new IllegalArgumentException("Despacho no encontrado con ID: " + despachoId));

        if (despacho.getEstado() != EstadoDespacho.PENDIENTE) {
            throw new IllegalStateException("La ruta no se encuentra en estado pendiente de aprobacion.");
        }

        despacho.setEstado(EstadoDespacho.EN_CURSO);
        despacho.setFechaInicioRuta(LocalDateTime.now());

        Pedido pedido = despacho.getPedido();
        pedido.setEstado(EstadoPedido.EN_RUTA);
        pedidoRepository.save(pedido);

        Chofer chofer = despacho.getChofer();
        chofer.setEstadoDisponibilidad(EstadoChofer.EN_RUTA);
        choferRepository.save(chofer);

        if (despacho.getRuta() != null && despacho.getRuta().getEstado() == EstadoRuta.PENDIENTE) {
            Ruta ruta = despacho.getRuta();
            ruta.setEstado(EstadoRuta.EN_CURSO);
            ruta.setFechaInicio(LocalDateTime.now());
            rutaRepository.save(ruta);
        }

        Despacho actualizado = despachoRepository.save(despacho);
        log.info("Chofer {} ha iniciado el despacho: {}", chofer.getNombre(), despachoId);

        DespachoResponse response = mapearADespachoResponse(actualizado);

        messagingTemplate.convertAndSend("/topic/despachos/" + despachoId + "/estado",
                Map.of("despachoId", despachoId.toString(), "estado", "EN_CURSO", "mensaje", "Ruta iniciada por chofer"));
        notificarActualizacionTablero();

        return response;
    }

    @Override
    @Transactional
    public DespachoResponse cancelarRuta(UUID despachoId, String motivo) {
        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new IllegalArgumentException("Despacho no encontrado con ID: " + despachoId));

        if (despacho.getEstado() == EstadoDespacho.ENTREGADO) {
            throw new IllegalStateException("No se puede cancelar una entrega ya completada y documentada.");
        }

        despacho.setEstado(EstadoDespacho.CANCELADA);
        despacho.setComentarios(motivo != null ? "Cancelada por chofer: " + motivo : "Cancelada por chofer voluntariamente.");

        Pedido pedido = despacho.getPedido();
        pedido.setEstado(EstadoPedido.CANCELADO);
        pedidoRepository.save(pedido);

        Despacho actualizado = despachoRepository.save(despacho);

        // Verificar si la ruta matriz debe completarse o cerrarse
        if (despacho.getRuta() != null) {
            actualizarEstadoRutaMatriz(despacho.getRuta());
        } else {
            Chofer chofer = despacho.getChofer();
            chofer.setEstadoDisponibilidad(EstadoChofer.DISPONIBLE);
            choferRepository.save(chofer);
        }

        log.warn("Despacho cancelado por chofer: {}. Motivo: {}", despachoId, motivo);

        messagingTemplate.convertAndSend("/topic/despachos/" + despachoId + "/estado",
                Map.of("despachoId", despachoId.toString(), "estado", "CANCELADA", "mensaje", "Streaming de ubicacion cortado"));
        notificarActualizacionTablero();

        return mapearADespachoResponse(actualizado);
    }

    @Override
    @Transactional
    public DespachoResponse cerrarEntrega(UUID despachoId, CerrarEntregaRequest request) {
        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new IllegalArgumentException("Despacho no encontrado con ID: " + despachoId));

        if (despacho.getEstado() == EstadoDespacho.ENTREGADO) {
            throw new IllegalStateException("La entrega ya fue registrada previamente.");
        }

        if (request.getFotoPodUrl() == null || request.getFotoPodUrl().trim().isEmpty()) {
            throw new IllegalArgumentException("CP-LOG-01: La evidencia fotografica del vidrio es estrictamente requerida.");
        }
        if (request.getFirmaUrl() == null || request.getFirmaUrl().trim().isEmpty()) {
            throw new IllegalArgumentException("CP-LOG-01: La firma digital tactil del receptor es estrictamente requerida.");
        }
        if (request.getLatitud() == null || request.getLongitud() == null) {
            throw new IllegalArgumentException("CP-LOG-01: Las coordenadas GPS de telemetria en sitio son estrictamente requeridas.");
        }

        Point puntoEntrega = GeometryUtil.crearPunto(request.getLatitud(), request.getLongitud());
        despacho.setCoordenadaEntrega(puntoEntrega);
        despacho.setFotoPodUrl(request.getFotoPodUrl());
        despacho.setFirmaUrl(request.getFirmaUrl());
        despacho.setFechaEntrega(LocalDateTime.now());
        despacho.setComentarios(request.getComentarios());

        // HU-06 y CP-LOG-02: Calculo de desviacion espacial con PostGIS y Haversine con tolerancia de 150m
        Point puntoDestino = despacho.getPedido().getCoordenadaDestino();
        double distanciaCalculada = GeoDistanceCalculator.calcularDistanciaPuntos(puntoEntrega, puntoDestino);

        despacho.setDesviacionMetros(distanciaCalculada);
        boolean desvioExcesivo = distanciaCalculada > UMBRAL_ALERTA_DESVIACION_METROS;
        despacho.setAlertaDesviacion(desvioExcesivo);

        despacho.setEstado(EstadoDespacho.ENTREGADO);

        Pedido pedido = despacho.getPedido();
        pedido.setEstado(EstadoPedido.ENTREGADO);
        pedidoRepository.save(pedido);

        Despacho guardado = despachoRepository.save(despacho);

        // Si pertenece a una ruta consolidada, verificar si todas las paradas han terminado
        if (despacho.getRuta() != null) {
            actualizarEstadoRutaMatriz(despacho.getRuta());
        } else {
            Chofer chofer = despacho.getChofer();
            chofer.setEstadoDisponibilidad(EstadoChofer.DISPONIBLE);
            choferRepository.save(chofer);
        }

        messagingTemplate.convertAndSend("/topic/despachos/" + despachoId + "/estado",
                Map.of("despachoId", despachoId.toString(), "estado", "ENTREGADO", "mensaje", "Entrega completada"));
        notificarActualizacionTablero();

        return mapearADespachoResponse(guardado);
    }

    private void actualizarEstadoRutaMatriz(Ruta ruta) {
        List<Despacho> paradas = despachoRepository.findByChoferId(ruta.getChofer().getId()).stream()
                .filter(d -> d.getRuta() != null && d.getRuta().getId().equals(ruta.getId()))
                .collect(Collectors.toList());

        boolean todasFinalizadas = paradas.stream().allMatch(
                d -> d.getEstado() == EstadoDespacho.ENTREGADO || d.getEstado() == EstadoDespacho.CANCELADA
        );

        if (todasFinalizadas && !paradas.isEmpty()) {
            boolean todasCanceladas = paradas.stream().allMatch(d -> d.getEstado() == EstadoDespacho.CANCELADA);
            ruta.setEstado(todasCanceladas ? EstadoRuta.CANCELADA : EstadoRuta.COMPLETADA);
            ruta.setFechaFin(LocalDateTime.now());
            rutaRepository.save(ruta);

            Chofer chofer = ruta.getChofer();
            chofer.setEstadoDisponibilidad(EstadoChofer.DISPONIBLE);
            choferRepository.save(chofer);
            log.info("Ruta consolidada {} finalizada con estado: {}", ruta.getId(), ruta.getEstado());
        }
    }

    @Override
    @Transactional(readOnly = true)
    public List<DespachoResponse> listarDespachos() {
        return despachoRepository.findAllByOrderByFechaAsignacionDesc().stream()
                .map(this::mapearADespachoResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public List<DespachoResponse> listarDespachosHoyChofer(UUID choferId) {
        return despachoRepository.findByChoferId(choferId).stream()
                .map(this::mapearADespachoResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public EvidenciaPodResponse obtenerEvidenciaPod(UUID despachoId) {
        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new IllegalArgumentException("Despacho no encontrado con ID: " + despachoId));

        if (despacho.getEstado() != EstadoDespacho.ENTREGADO) {
            throw new IllegalStateException("El despacho aun no ha sido entregado, por lo que no posee e-PoD.");
        }

        return EvidenciaPodResponse.builder()
                .despachoId(despacho.getId())
                .cliente(despacho.getPedido().getCliente())
                .direccionCliente(despacho.getPedido().getDireccionTexto())
                .choferNombre(despacho.getChofer().getNombre())
                .choferEmail(despacho.getChofer().getEmail())
                .fotoPodUrl(despacho.getFotoPodUrl())
                .firmaUrl(despacho.getFirmaUrl())
                .latitudEntrega(GeometryUtil.extraerLatitud(despacho.getCoordenadaEntrega()))
                .longitudEntrega(GeometryUtil.extraerLongitud(despacho.getCoordenadaEntrega()))
                .latitudCliente(GeometryUtil.extraerLatitud(despacho.getPedido().getCoordenadaDestino()))
                .longitudCliente(GeometryUtil.extraerLongitud(despacho.getPedido().getCoordenadaDestino()))
                .desviacionMetros(despacho.getDesviacionMetros())
                .alertaDesviacion(despacho.getAlertaDesviacion())
                .fechaEntrega(despacho.getFechaEntrega())
                .comentarios(despacho.getComentarios())
                .build();
    }

    private void notificarActualizacionTablero() {
        try {
            messagingTemplate.convertAndSend("/topic/tablero-actualizaciones", Map.of("timestamp", System.currentTimeMillis()));
        } catch (Exception e) {
            log.warn("No se pudo emitir evento de actualizacion de tablero: {}", e.getMessage());
        }
    }

    private PedidoResponse mapearAPedidoResponse(Pedido p) {
        return PedidoResponse.builder()
                .id(p.getId())
                .cliente(p.getCliente())
                .direccionTexto(p.getDireccionTexto())
                .latitudDestino(GeometryUtil.extraerLatitud(p.getCoordenadaDestino()))
                .longitudDestino(GeometryUtil.extraerLongitud(p.getCoordenadaDestino()))
                .estado(p.getEstado())
                .fechaSolicitud(p.getFechaSolicitud())
                .build();
    }

    private ChoferResponse mapearAChoferResponse(Chofer c) {
        if (c == null) {
            return null;
        }
        return ChoferResponse.builder()
                .id(c.getId())
                .nombre(c.getNombre())
                .email(c.getEmail())
                .telefono(c.getTelefono())
                .estadoDisponibilidad(c.getEstadoDisponibilidad())
                .createdAt(c.getCreatedAt())
                .build();
    }

    private DespachoResponse mapearADespachoResponse(Despacho d) {
        return DespachoResponse.builder()
                .id(d.getId())
                .rutaId(d.getRuta() != null ? d.getRuta().getId() : null)
                .ordenParada(d.getOrdenParada())
                .pedido(mapearAPedidoResponse(d.getPedido()))
                .chofer(mapearAChoferResponse(d.getChofer()))
                .fechaAsignacion(d.getFechaAsignacion())
                .fechaInicioRuta(d.getFechaInicioRuta())
                .fechaEntrega(d.getFechaEntrega())
                .fotoPodUrl(d.getFotoPodUrl())
                .firmaUrl(d.getFirmaUrl())
                .latitudEntrega(GeometryUtil.extraerLatitud(d.getCoordenadaEntrega()))
                .longitudEntrega(GeometryUtil.extraerLongitud(d.getCoordenadaEntrega()))
                .desviacionMetros(d.getDesviacionMetros())
                .alertaDesviacion(d.getAlertaDesviacion())
                .estado(d.getEstado())
                .comentarios(d.getComentarios())
                .build();
    }

    private RutaResponse mapearARutaResponse(Ruta r) {
        List<DespachoResponse> paradasList = r.getParadas() != null
                ? r.getParadas().stream().map(this::mapearADespachoResponse).collect(Collectors.toList())
                : Collections.emptyList();

        return RutaResponse.builder()
                .id(r.getId())
                .codigoRuta(r.getCodigoRuta())
                .choferId(r.getChofer() != null ? r.getChofer().getId() : null)
                .choferNombre(r.getChofer() != null ? r.getChofer().getNombre() : "Sin asignar")
                .choferTelefono(r.getChofer() != null ? r.getChofer().getTelefono() : null)
                .estado(r.getEstado())
                .fechaCreacion(r.getFechaCreacion())
                .fechaInicio(r.getFechaInicio())
                .fechaFin(r.getFechaFin())
                .comentarios(r.getComentarios())
                .paradas(paradasList)
                .build();
    }

    @Override
    @Transactional
    public RutaResponse crearRuta(CrearRutaSimpleRequest request) {
        String codigoBase = (request.getCodigoRuta() != null && !request.getCodigoRuta().trim().isEmpty())
                ? request.getCodigoRuta().trim()
                : "Ruta 1";
        String codigoRuta = codigoBase;
        if (rutaRepository.existsByCodigoRuta(codigoRuta)) {
            codigoRuta = codigoBase + " (" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss")) + ")";
        }

        Chofer chofer = null;
        if (request.getChoferId() != null) {
            chofer = choferRepository.findById(request.getChoferId()).orElse(null);
        }

        Ruta ruta = Ruta.builder()
                .codigoRuta(codigoRuta)
                .chofer(chofer)
                .estado(EstadoRuta.PENDIENTE)
                .fechaCreacion(LocalDateTime.now())
                .comentarios(request.getComentarios())
                .paradas(new ArrayList<>())
                .build();

        Ruta guardada = rutaRepository.save(ruta);
        notificarActualizacionTablero();
        return mapearARutaResponse(guardada);
    }

    @Override
    @Transactional
    public RutaResponse asignarChoferRuta(UUID rutaId, UUID choferId) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));

        Chofer chofer = null;
        if (choferId != null) {
            chofer = choferRepository.findById(choferId)
                    .orElseThrow(() -> new IllegalArgumentException("Chofer no encontrado con ID: " + choferId));
        }

        ruta.setChofer(chofer);

        if (ruta.getParadas() != null) {
            for (Despacho d : ruta.getParadas()) {
                d.setChofer(chofer);
                despachoRepository.save(d);
            }
        }

        Ruta guardada = rutaRepository.save(ruta);
        if (chofer != null) {
            RutaResponse res = mapearARutaResponse(guardada);
            messagingTemplate.convertAndSend("/topic/choferes/" + chofer.getId() + "/rutas-asignadas", res);
        }
        notificarActualizacionTablero();
        return mapearARutaResponse(guardada);
    }

    @Override
    @Transactional
    public RutaResponse agregarDestinoRuta(UUID rutaId, DestinoRutaRequest request) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));

        if (ruta.getEstado() == EstadoRuta.COMPLETADA || ruta.getEstado() == EstadoRuta.CANCELADA) {
            throw new IllegalStateException("No se pueden agregar destinos a una ruta completada o cancelada.");
        }

        Point puntoDestino = GeometryUtil.crearPunto(request.getLatitudDestino(), request.getLongitudDestino());
        Pedido pedido = Pedido.builder()
                .cliente(request.getCliente().trim())
                .direccionTexto(request.getDireccionTexto().trim())
                .coordenadaDestino(puntoDestino)
                .estado(ruta.getEstado() == EstadoRuta.EN_CURSO ? EstadoPedido.EN_RUTA : EstadoPedido.PENDIENTE)
                .fechaSolicitud(LocalDateTime.now())
                .build();
        Pedido pedidoGuardado = pedidoRepository.save(pedido);

        int siguienteOrden = (ruta.getParadas() != null ? ruta.getParadas().size() : 0) + 1;

        Despacho despacho = Despacho.builder()
                .ruta(ruta)
                .ordenParada(siguienteOrden)
                .pedido(pedidoGuardado)
                .chofer(ruta.getChofer())
                .fechaAsignacion(LocalDateTime.now())
                .estado(ruta.getEstado() == EstadoRuta.EN_CURSO ? EstadoDespacho.EN_CURSO : EstadoDespacho.PENDIENTE)
                .comentarios(request.getComentarios())
                .build();
        despachoRepository.save(despacho);

        if (ruta.getParadas() == null) {
            ruta.setParadas(new ArrayList<>());
        }
        ruta.getParadas().add(despacho);
        Ruta guardada = rutaRepository.save(ruta);

        if (ruta.getChofer() != null) {
            RutaResponse res = mapearARutaResponse(guardada);
            messagingTemplate.convertAndSend("/topic/choferes/" + ruta.getChofer().getId() + "/rutas-asignadas", res);
        }
        notificarActualizacionTablero();
        return mapearARutaResponse(guardada);
    }

    @Override
    @Transactional
    public RutaResponse modificarDestinoRuta(UUID rutaId, UUID despachoId, DestinoRutaRequest request) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));

        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new IllegalArgumentException("Parada no encontrada con ID: " + despachoId));

        Pedido pedido = despacho.getPedido();
        if (request.getCliente() != null && !request.getCliente().isBlank()) {
            pedido.setCliente(request.getCliente().trim());
        }
        if (request.getDireccionTexto() != null && !request.getDireccionTexto().isBlank()) {
            pedido.setDireccionTexto(request.getDireccionTexto().trim());
        }
        if (request.getLatitudDestino() != null && request.getLongitudDestino() != null) {
            Point punto = GeometryUtil.crearPunto(request.getLatitudDestino(), request.getLongitudDestino());
            pedido.setCoordenadaDestino(punto);
        }
        pedidoRepository.save(pedido);

        if (request.getComentarios() != null) {
            despacho.setComentarios(request.getComentarios());
        }
        despachoRepository.save(despacho);

        Ruta guardada = rutaRepository.findById(rutaId).orElse(ruta);
        if (guardada.getChofer() != null) {
            RutaResponse res = mapearARutaResponse(guardada);
            messagingTemplate.convertAndSend("/topic/choferes/" + guardada.getChofer().getId() + "/rutas-asignadas", res);
        }
        notificarActualizacionTablero();
        return mapearARutaResponse(guardada);
    }

    @Override
    @Transactional
    public RutaResponse eliminarDestinoRuta(UUID rutaId, UUID despachoId) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));

        Despacho despacho = despachoRepository.findById(despachoId)
                .orElseThrow(() -> new IllegalArgumentException("Parada no encontrada con ID: " + despachoId));

        if (despacho.getEstado() == EstadoDespacho.ENTREGADO) {
            throw new IllegalStateException("No se puede eliminar una parada que ya fue entregada y cuenta con e-PoD.");
        }

        ruta.getParadas().remove(despacho);
        despachoRepository.delete(despacho);

        int orden = 1;
        for (Despacho d : ruta.getParadas()) {
            d.setOrdenParada(orden++);
            despachoRepository.save(d);
        }

        Ruta guardada = rutaRepository.save(ruta);
        if (guardada.getChofer() != null) {
            RutaResponse res = mapearARutaResponse(guardada);
            messagingTemplate.convertAndSend("/topic/choferes/" + guardada.getChofer().getId() + "/rutas-asignadas", res);
        }
        notificarActualizacionTablero();
        return mapearARutaResponse(guardada);
    }

    @Override
    @Transactional
    public RutaResponse optimizarRuta(UUID rutaId) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));

        List<Despacho> paradas = ruta.getParadas();
        if (paradas == null || paradas.size() <= 1) {
            return mapearARutaResponse(ruta);
        }

        List<Pedido> pedidos = paradas.stream().map(Despacho::getPedido).collect(Collectors.toList());
        List<Pedido> pedidosOptimizados = ordenarPedidosPorProximidad(pedidos, LAT_BODEGA_QUITO, LON_BODEGA_QUITO);

        int orden = 1;
        for (Pedido p : pedidosOptimizados) {
            for (Despacho d : paradas) {
                if (d.getPedido().getId().equals(p.getId())) {
                    d.setOrdenParada(orden++);
                    despachoRepository.save(d);
                    break;
                }
            }
        }

        Ruta guardada = rutaRepository.findById(rutaId).orElse(ruta);
        if (guardada.getChofer() != null) {
            RutaResponse res = mapearARutaResponse(guardada);
            messagingTemplate.convertAndSend("/topic/choferes/" + guardada.getChofer().getId() + "/rutas-asignadas", res);
        }
        notificarActualizacionTablero();
        return mapearARutaResponse(guardada);
    }

    @Override
    @Transactional
    public void eliminarRuta(UUID rutaId) {
        Ruta ruta = rutaRepository.findById(rutaId)
                .orElseThrow(() -> new IllegalArgumentException("Ruta no encontrada con ID: " + rutaId));

        if (ruta.getEstado() == EstadoRuta.EN_CURSO) {
            throw new IllegalStateException("No se puede eliminar una ruta que ya se encuentra en transito. Cancelar primero.");
        }

        if (ruta.getChofer() != null && ruta.getChofer().getEstadoDisponibilidad() == EstadoChofer.EN_RUTA) {
            ruta.getChofer().setEstadoDisponibilidad(EstadoChofer.DISPONIBLE);
            choferRepository.save(ruta.getChofer());
        }

        rutaRepository.delete(ruta);
        notificarActualizacionTablero();
    }

    @Override
    @Transactional
    public void eliminarChofer(UUID choferId) {
        choferRepository.findById(choferId).ifPresent(chofer -> {
            List<Ruta> rutas = rutaRepository.findByChoferIdOrderByFechaCreacionDesc(choferId);
            for (Ruta r : rutas) {
                if (r.getEstado() == EstadoRuta.PENDIENTE) {
                    r.setChofer(null);
                    if (r.getParadas() != null) {
                        for (Despacho d : r.getParadas()) {
                            d.setChofer(null);
                            despachoRepository.save(d);
                        }
                    }
                    rutaRepository.save(r);
                }
            }
            choferRepository.delete(chofer);
            log.info("Chofer con ID {} eliminado del modulo logistico.", choferId);
        });
        notificarActualizacionTablero();
    }
}
