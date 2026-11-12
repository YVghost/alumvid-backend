package com.alumvid.logistica.service;

import com.alumvid.logistica.dto.*;
import com.alumvid.logistica.model.*;
import com.alumvid.logistica.repository.ChoferRepository;
import com.alumvid.logistica.repository.DespachoRepository;
import com.alumvid.logistica.repository.PedidoRepository;
import com.alumvid.logistica.repository.RutaRepository;
import com.alumvid.logistica.security.AuthClient;
import com.alumvid.logistica.security.Sesion;
import com.alumvid.logistica.util.GeoDistanceCalculator;
import com.alumvid.logistica.util.GeometryUtil;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.locationtech.jts.geom.Point;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Rutas y paradas de reparto. Cada parada nace de un pedido comercial: logística
 * guarda el destino y el manifiesto de carga; pedidos registra la custodia del
 * material (despacho, entrega, devolución) y mueve el inventario.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class LogisticaServiceImpl implements LogisticaService {

    private static final double UMBRAL_ALERTA_DESVIACION_METROS = 150.0;
    private static final double LAT_BODEGA_QUITO = -0.089290;
    private static final double LON_BODEGA_QUITO = -78.439607;
    private static final Set<EstadoDespacho> FINALES = EnumSet.of(EstadoDespacho.ENTREGADO, EstadoDespacho.CANCELADA);

    private final ChoferRepository choferRepository;
    private final PedidoRepository pedidoRepository;
    private final DespachoRepository despachoRepository;
    private final RutaRepository rutaRepository;
    private final SimpMessagingTemplate messagingTemplate;
    private final GoogleRoutesService googleRoutesService;
    private final JdbcTemplate jdbcTemplate;
    private final CommercialOrderBridge commercialBridge;
    private final PedidosClient pedidosClient;
    private final AuthClient authClient;
    private final ObjectMapper json;

    // =====================================================================
    // Utilidades
    // =====================================================================

    private static ResponseStatusException conflicto(String mensaje) {
        return new ResponseStatusException(HttpStatus.CONFLICT, mensaje);
    }

    private Ruta ruta(UUID id) {
        return rutaRepository.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Ruta no encontrada"));
    }

    private Despacho despacho(UUID id) {
        return despachoRepository.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Parada no encontrada"));
    }

    private static void exigirPendiente(Ruta r, String accion) {
        if (r.getEstado() != EstadoRuta.PENDIENTE) {
            throw conflicto("Solo se puede " + accion + " en una ruta pendiente (esta ruta está " + r.getEstado().name().toLowerCase().replace('_', ' ') + ")");
        }
    }

    /** Un chofer está ocupado si tiene una ruta en curso (distinta de la indicada) con paradas por atender. */
    private boolean ocupado(UUID choferId, UUID excluirRuta) {
        return rutaRepository.findByChoferIdAndEstadoIn(choferId, List.of(EstadoRuta.EN_CURSO)).stream()
                .filter(r -> !r.getId().equals(excluirRuta))
                .anyMatch(r -> r.getParadas().stream().anyMatch(d -> !FINALES.contains(d.getEstado())));
    }

    /**
     * Sincroniza la identidad de los choferes desde usuarios (dueño de las cuentas)
     * y calcula su disponibilidad: INACTIVO, EN_RUTA o DISPONIBLE.
     */
    private void sincronizarChoferes() {
        var activos = new HashSet<UUID>();
        for (var u : authClient.activeDrivers(Sesion.token())) {
            if (Boolean.TRUE.equals(u.get("mustChangePassword")) || Boolean.FALSE.equals(u.get("active"))) continue;
            UUID id = UUID.fromString(String.valueOf(u.get("id")));
            String nombre = String.valueOf(u.getOrDefault("fullName", "Chofer"));
            String email = String.valueOf(u.getOrDefault("email", id + "@alumvid.local")).toLowerCase(Locale.ROOT);
            String telefono = u.get("telefono") == null ? "" : String.valueOf(u.get("telefono"));
            activos.add(id);
            jdbcTemplate.update("INSERT INTO logistica.choferes(id,nombre,email,telefono,estado_disponibilidad,created_at,updated_at) "
                    + "VALUES (?,?,?,?,'DISPONIBLE',NOW(),NOW()) ON CONFLICT DO NOTHING", id, nombre, email, telefono);
            jdbcTemplate.update("UPDATE logistica.choferes SET nombre=?,telefono=?,updated_at=NOW() WHERE id=?", nombre, telefono, id);
            jdbcTemplate.update("UPDATE logistica.choferes SET email=? WHERE id=? AND NOT EXISTS "
                    + "(SELECT 1 FROM logistica.choferes o WHERE o.email=? AND o.id<>?)", email, id, email, id);
        }
        for (Chofer c : choferRepository.findAll()) {
            EstadoChofer estado = !activos.contains(c.getId()) ? EstadoChofer.INACTIVO
                    : ocupado(c.getId(), null) ? EstadoChofer.EN_RUTA : EstadoChofer.DISPONIBLE;
            if (c.getEstadoDisponibilidad() != estado) {
                c.setEstadoDisponibilidad(estado);
                choferRepository.save(c);
            }
        }
    }

    /** Solo se asignan choferes activos que no estén en ruta. */
    private Chofer choferDisponible(UUID choferId, UUID rutaActual) {
        sincronizarChoferes();
        Chofer chofer = choferRepository.findById(choferId)
                .orElseThrow(() -> conflicto("El chofer no existe o no tiene el rol CHOFER"));
        if (chofer.getEstadoDisponibilidad() == EstadoChofer.INACTIVO) {
            throw conflicto(chofer.getNombre() + " está inactivo o aún no cambia su clave temporal");
        }
        if (ocupado(choferId, rutaActual)) {
            throw conflicto(chofer.getNombre() + " está en ruta; podrás asignarlo cuando termine su recorrido");
        }
        return chofer;
    }

    private void avisarChofer(Ruta r) {
        if (r.getChofer() != null) {
            messagingTemplate.convertAndSend("/topic/choferes/" + r.getChofer().getId() + "/rutas-asignadas", mapearARutaResponse(r));
        }
    }

    private void notificarActualizacionTablero() {
        try {
            messagingTemplate.convertAndSend("/topic/tablero-actualizaciones", Map.of("timestamp", System.currentTimeMillis()));
        } catch (Exception e) {
            log.warn("No se pudo emitir evento de actualizacion de tablero: {}", e.getMessage());
        }
    }

    private UUID envioDe(Despacho d) {
        if (d.getEnvioComercialId() != null) return d.getEnvioComercialId();
        return commercialBridge.envioDe(d.getId()).orElse(null);
    }

    /** Devuelve a bodega (sin salida física) el material de una parada de ruta pendiente. */
    private void anularEnvio(Despacho d, String motivo) {
        UUID envio = envioDe(d);
        if (envio != null) pedidosClient.anular(envio, motivo);
    }

    /**
     * Si el pedido se canceló o venció en pedidos, su parada queda cancelada aquí.
     * Logística solo lee el estado del envío; no modifica datos de pedidos.
     */
    private void sincronizarConPedidos(Collection<Ruta> rutas) {
        var abiertas = rutas.stream()
                .filter(r -> r.getEstado() == EstadoRuta.PENDIENTE || r.getEstado() == EstadoRuta.EN_CURSO)
                .flatMap(r -> r.getParadas().stream())
                .filter(d -> !FINALES.contains(d.getEstado()))
                .collect(Collectors.toMap(Despacho::getId, d -> d));
        if (abiertas.isEmpty()) {
            rutas.stream().filter(r -> r.getEstado() == EstadoRuta.EN_CURSO).toList().forEach(this::cerrarRutaSiTermino);
            return;
        }
        var estados = commercialBridge.estados(abiertas.keySet());
        // Rutas en curso cuyas paradas ya terminaron (p. ej. datos previos) se cierran.
        var tocadas = rutas.stream().filter(r -> r.getEstado() == EstadoRuta.EN_CURSO)
                .collect(Collectors.toCollection(HashSet::new));
        for (var e : estados.entrySet()) {
            if (!Set.of("RETORNO_PENDIENTE", "DEVUELTO_BODEGA").contains(e.getValue())) continue;
            Despacho d = abiertas.get(e.getKey());
            d.setEstado(EstadoDespacho.CANCELADA);
            d.setComentarios("El pedido fue cancelado o venció: el material vuelve a bodega");
            d.getPedido().setEstado(EstadoPedido.CANCELADO);
            pedidoRepository.save(d.getPedido());
            despachoRepository.save(d);
            tocadas.add(d.getRuta());
        }
        tocadas.forEach(this::cerrarRutaSiTermino);
    }

    /** Una ruta en curso se completa sola cuando todas sus paradas terminan. */
    private void cerrarRutaSiTermino(Ruta ruta) {
        if (ruta == null || ruta.getEstado() != EstadoRuta.EN_CURSO) return;
        var paradas = ruta.getParadas();
        if (paradas.isEmpty() || !paradas.stream().allMatch(d -> FINALES.contains(d.getEstado()))) return;
        for (Despacho d : paradas) {
            if (d.getEstado() == EstadoDespacho.CANCELADA) {
                // El material salió con el chofer y no se entregó: bodega debe recibirlo.
                commercialBridge.cancelled(d.getId(), d.getComentarios() != null ? d.getComentarios() : "No entregado en ruta");
            }
        }
        ruta.setEstado(EstadoRuta.COMPLETADA);
        ruta.setFechaFin(LocalDateTime.now());
        rutaRepository.save(ruta);
        if (ruta.getChofer() != null && !ocupado(ruta.getChofer().getId(), ruta.getId())) {
            ruta.getChofer().setEstadoDisponibilidad(EstadoChofer.DISPONIBLE);
            choferRepository.save(ruta.getChofer());
        }
        messagingTemplate.convertAndSend("/topic/rutas/" + ruta.getId() + "/estado",
                Map.of("rutaId", ruta.getId().toString(), "estado", "COMPLETADA", "mensaje", "Todas las paradas finalizaron"));
        notificarActualizacionTablero();
    }

    private void reordenar(Ruta ruta) {
        int orden = 1;
        for (Despacho d : ruta.getParadas().stream().sorted(Comparator.comparing(Despacho::getOrdenParada)).toList()) {
            d.setOrdenParada(orden++);
        }
    }

    // =====================================================================
    // Choferes
    // =====================================================================

    @Override
    @Transactional
    public List<ChoferResponse> listarChoferes() {
        sincronizarChoferes();
        return choferRepository.findAll().stream()
                .sorted(Comparator.comparing(Chofer::getNombre, String.CASE_INSENSITIVE_ORDER))
                .map(this::mapearAChoferResponse)
                .collect(Collectors.toList());
    }

    // =====================================================================
    // Planificación
    // =====================================================================

    @Override
    @Transactional
    public RutaResponse crearRuta(CrearRutaSimpleRequest request) {
        Chofer chofer = choferDisponible(request.getChoferId(), null);
        String base = request.getCodigoRuta() != null && !request.getCodigoRuta().isBlank()
                ? request.getCodigoRuta().trim()
                : "RUTA-" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmm"));
        String codigo = rutaRepository.existsByCodigoRuta(base)
                ? base + " (" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss")) + ")"
                : base;
        Ruta ruta = rutaRepository.save(Ruta.builder()
                .codigoRuta(codigo)
                .chofer(chofer)
                .estado(EstadoRuta.PENDIENTE)
                .fechaCreacion(LocalDateTime.now())
                .comentarios(request.getComentarios())
                .paradas(new ArrayList<>())
                .build());
        if (request.getPedidos() != null && !request.getPedidos().isEmpty()) {
            agregar(ruta, request.getPedidos());
        }
        notificarActualizacionTablero();
        avisarChofer(ruta);
        return mapearARutaResponse(ruta);
    }

    @Override
    @Transactional
    public RutaResponse agregarPedidos(UUID rutaId, AgregarPedidosRequest request) {
        Ruta ruta = ruta(rutaId);
        exigirPendiente(ruta, "agregar pedidos");
        if (ruta.getChofer() == null) throw conflicto("Asigna un chofer antes de agregar pedidos");
        choferDisponible(ruta.getChofer().getId(), ruta.getId());
        agregar(ruta, request.getPedidos());
        notificarActualizacionTablero();
        avisarChofer(ruta);
        return mapearARutaResponse(ruta);
    }

    /**
     * Crea una parada por pedido. Si pedidos rechaza alguno, se anulan los
     * despachos ya registrados en este lote y la transacción se revierte.
     */
    private void agregar(Ruta ruta, List<PedidoRutaRequest> pedidos) {
        var enRuta = ruta.getParadas().stream()
                .filter(d -> d.getPedidoComercialId() != null && d.getEstado() != EstadoDespacho.CANCELADA)
                .map(Despacho::getPedidoComercialId).collect(Collectors.toSet());
        var registrados = new ArrayList<UUID>();
        try {
            int orden = ruta.getParadas().size() + 1;
            for (PedidoRutaRequest item : pedidos) {
                if (!enRuta.add(item.getPedidoId())) {
                    throw conflicto("El pedido ya está en esta ruta");
                }
                Despacho d = crearParada(ruta, item, orden++);
                registrados.add(d.getEnvioComercialId());
            }
        } catch (RuntimeException e) {
            for (UUID envio : registrados) {
                try {
                    pedidosClient.anular(envio, "Ruta no creada: se revierte el despacho");
                } catch (RuntimeException ignored) {
                    log.error("No se pudo revertir el envío {} tras un error al armar la ruta", envio);
                }
            }
            throw e;
        }
    }

    @SuppressWarnings("unchecked")
    private Despacho crearParada(Ruta ruta, PedidoRutaRequest item, int orden) {
        var pedido = (Map<String, Object>) pedidosClient.pedido(item.getPedidoId()).get("order");
        Integer numero = pedido.get("number") instanceof Number n ? n.intValue() : null;
        if (!"ENTREGA".equals(pedido.get("delivery_mode"))) {
            throw conflicto("El pedido #" + numero + " es para retiro en local");
        }
        Double lat = item.getLatitud() != null ? item.getLatitud() : numero(pedido.get("delivery_latitude"));
        Double lon = item.getLongitud() != null ? item.getLongitud() : numero(pedido.get("delivery_longitude"));
        if (lat == null || lon == null) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "El pedido #" + numero + " no tiene ubicación de entrega; márcala en el mapa");
        }
        Pedido destino = pedidoRepository.save(Pedido.builder()
                .cliente(texto(pedido.get("client_name"), "Cliente"))
                .direccionTexto(texto(pedido.get("delivery_address"), "Dirección de entrega"))
                .coordenadaDestino(GeometryUtil.crearPunto(lat, lon))
                .estado(EstadoPedido.PENDIENTE)
                .fechaSolicitud(LocalDateTime.now())
                .build());
        Despacho parada = despachoRepository.save(Despacho.builder()
                .ruta(ruta)
                .ordenParada(orden)
                .pedido(destino)
                .chofer(ruta.getChofer())
                .fechaAsignacion(LocalDateTime.now())
                .estado(EstadoDespacho.PENDIENTE)
                .pedidoComercialId(item.getPedidoId())
                .numeroPedido(numero)
                .build());
        List<Map<String, Object>> lineas = item.getLineas() == null ? null : item.getLineas().stream()
                .map(l -> Map.<String, Object>of("lineId", l.getLineId(), "quantity", l.getQuantity()))
                .toList();
        var envio = pedidosClient.despachar(item.getPedidoId(), ruta.getChofer().getId(), ruta.getId(),
                parada.getId(), destino.getId(), lineas, "Despacho en ruta " + ruta.getCodigoRuta());
        parada.setEnvioComercialId(UUID.fromString(String.valueOf(envio.get("id"))));
        try {
            parada.setCarga(json.writeValueAsString(envio.get("items")));
        } catch (Exception e) {
            parada.setCarga("[]");
        }
        despachoRepository.save(parada);
        ruta.getParadas().add(parada);
        return parada;
    }

    private static Double numero(Object v) {
        if (v == null) return null;
        try {
            return Double.parseDouble(v.toString());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static String texto(Object v, String porDefecto) {
        return v == null || v.toString().isBlank() ? porDefecto : v.toString();
    }

    @Override
    @Transactional
    public RutaResponse modificarCarga(UUID rutaId, UUID despachoId, ModificarCargaRequest request) {
        Ruta ruta = ruta(rutaId);
        exigirPendiente(ruta, "modificar la carga");
        Despacho anterior = despacho(despachoId);
        if (!ruta.getId().equals(anterior.getRuta().getId())) throw conflicto("La parada no pertenece a esta ruta");
        if (anterior.getPedidoComercialId() == null) throw conflicto("Esta parada no proviene de un pedido");
        int orden = anterior.getOrdenParada();
        var item = new PedidoRutaRequest(anterior.getPedidoComercialId(), request.getLineas(),
                GeometryUtil.extraerLatitud(anterior.getPedido().getCoordenadaDestino()),
                GeometryUtil.extraerLongitud(anterior.getPedido().getCoordenadaDestino()));
        anularEnvio(anterior, "Carga modificada antes de salir");
        ruta.getParadas().remove(anterior);
        despachoRepository.delete(anterior);
        pedidoRepository.delete(anterior.getPedido());
        despachoRepository.flush();
        crearParada(ruta, item, orden);
        notificarActualizacionTablero();
        avisarChofer(ruta);
        return mapearARutaResponse(ruta);
    }

    @Override
    @Transactional
    public RutaResponse eliminarDestinoRuta(UUID rutaId, UUID despachoId) {
        Ruta ruta = ruta(rutaId);
        exigirPendiente(ruta, "quitar paradas");
        Despacho d = despacho(despachoId);
        if (!ruta.getId().equals(d.getRuta().getId())) throw conflicto("La parada no pertenece a esta ruta");
        if (d.getEstado() != EstadoDespacho.CANCELADA) anularEnvio(d, "Pedido retirado de la ruta");
        ruta.getParadas().remove(d);
        despachoRepository.delete(d);
        pedidoRepository.delete(d.getPedido());
        reordenar(ruta);
        rutaRepository.save(ruta);
        notificarActualizacionTablero();
        avisarChofer(ruta);
        return mapearARutaResponse(ruta);
    }

    @Override
    @Transactional
    public RutaResponse asignarChoferRuta(UUID rutaId, UUID choferId) {
        Ruta ruta = ruta(rutaId);
        if (ruta.getEstado() == EstadoRuta.EN_CURSO) {
            throw conflicto("No se cambia el chofer de una ruta en curso");
        }
        exigirPendiente(ruta, "asignar chofer");
        Chofer chofer = choferDisponible(choferId, ruta.getId());
        boolean conPedidos = ruta.getParadas().stream().anyMatch(d -> d.getPedidoComercialId() != null);
        if (conPedidos) pedidosClient.reasignarChofer(ruta.getId(), chofer.getId());
        ruta.setChofer(chofer);
        ruta.getParadas().forEach(d -> d.setChofer(chofer));
        rutaRepository.save(ruta);
        notificarActualizacionTablero();
        avisarChofer(ruta);
        return mapearARutaResponse(ruta);
    }

    @Override
    @Transactional
    public void eliminarRuta(UUID rutaId) {
        Ruta ruta = ruta(rutaId);
        if (ruta.getEstado() != EstadoRuta.PENDIENTE) {
            throw conflicto("Solo se eliminan rutas pendientes; las demás se conservan como historial");
        }
        for (Despacho d : ruta.getParadas()) {
            if (d.getEstado() != EstadoDespacho.CANCELADA) anularEnvio(d, "Ruta eliminada antes de salir");
        }
        var destinos = ruta.getParadas().stream().map(Despacho::getPedido).toList();
        rutaRepository.delete(ruta);
        rutaRepository.flush();
        pedidoRepository.deleteAll(destinos);
        notificarActualizacionTablero();
    }

    @Override
    @Transactional
    public RutaResponse aceptarEIniciarRutaConsolidada(UUID rutaId) {
        Ruta ruta = ruta(rutaId);
        exigirPendiente(ruta, "iniciar");
        if (ruta.getChofer() == null) throw conflicto("Asigna un chofer antes de iniciar la ruta");
        if (ruta.getParadas().stream().noneMatch(d -> d.getEstado() == EstadoDespacho.PENDIENTE)) {
            throw conflicto("La ruta no tiene paradas pendientes");
        }
        if (ocupado(ruta.getChofer().getId(), ruta.getId())) {
            throw conflicto(ruta.getChofer().getNombre() + " ya está en otra ruta; debe terminarla antes de iniciar esta");
        }
        commercialBridge.route(rutaId, true);
        ruta.setEstado(EstadoRuta.EN_CURSO);
        ruta.setFechaInicio(LocalDateTime.now());
        ruta.getChofer().setEstadoDisponibilidad(EstadoChofer.EN_RUTA);
        choferRepository.save(ruta.getChofer());
        rutaRepository.save(ruta);
        messagingTemplate.convertAndSend("/topic/rutas/" + rutaId + "/estado",
                Map.of("rutaId", rutaId.toString(), "estado", "EN_CURSO", "mensaje", "Ruta iniciada"));
        notificarActualizacionTablero();
        avisarChofer(ruta);
        return mapearARutaResponse(ruta);
    }

    @Override
    @Transactional
    public RutaResponse cancelarRutaConsolidada(UUID rutaId, String motivo) {
        Ruta ruta = ruta(rutaId);
        if (ruta.getEstado() == EstadoRuta.COMPLETADA || ruta.getEstado() == EstadoRuta.CANCELADA) {
            throw conflicto("La ruta ya está finalizada");
        }
        String texto = motivo != null && !motivo.isBlank() ? motivo.trim() : "Ruta cancelada";
        boolean salio = ruta.getEstado() == EstadoRuta.EN_CURSO;
        for (Despacho d : ruta.getParadas()) {
            if (d.getEstado() == EstadoDespacho.ENTREGADO) continue;
            if (salio) {
                commercialBridge.cancelled(d.getId(), texto);   // el material vuelve con el chofer
            } else if (d.getEstado() != EstadoDespacho.CANCELADA) {
                anularEnvio(d, texto);                           // nunca salió de bodega
            }
            d.setEstado(EstadoDespacho.CANCELADA);
            d.setComentarios(texto);
            d.getPedido().setEstado(EstadoPedido.CANCELADO);
        }
        ruta.setEstado(EstadoRuta.CANCELADA);
        ruta.setFechaFin(LocalDateTime.now());
        ruta.setComentarios(ruta.getComentarios() == null ? "Cancelada: " + texto : ruta.getComentarios() + " · Cancelada: " + texto);
        if (ruta.getChofer() != null && !ocupado(ruta.getChofer().getId(), ruta.getId())) {
            ruta.getChofer().setEstadoDisponibilidad(EstadoChofer.DISPONIBLE);
            choferRepository.save(ruta.getChofer());
        }
        rutaRepository.save(ruta);
        messagingTemplate.convertAndSend("/topic/rutas/" + rutaId + "/estado",
                Map.of("rutaId", rutaId.toString(), "estado", "CANCELADA", "mensaje", texto));
        notificarActualizacionTablero();
        avisarChofer(ruta);
        return mapearARutaResponse(ruta);
    }

    @Override
    @Transactional
    public RutaResponse completarRutaConsolidada(UUID rutaId) {
        Ruta ruta = ruta(rutaId);
        if (ruta.getEstado() != EstadoRuta.EN_CURSO) throw conflicto("Solo se completa una ruta en curso");
        if (!ruta.getParadas().stream().allMatch(d -> FINALES.contains(d.getEstado()))) {
            throw conflicto("Aún hay paradas por atender; márcalas como entregadas o no entregadas, o cancela la ruta");
        }
        cerrarRutaSiTermino(ruta);
        return mapearARutaResponse(ruta);
    }

    // =====================================================================
    // Consulta
    // =====================================================================

    @Override
    @Transactional
    public List<RutaResponse> listarRutas() {
        var rutas = rutaRepository.findAllByOrderByFechaCreacionDesc();
        sincronizarConPedidos(rutas);
        return rutas.stream().map(this::mapearARutaResponse).collect(Collectors.toList());
    }

    @Override
    @Transactional
    public List<RutaResponse> listarRutasPorChofer(UUID choferId) {
        var rutas = rutaRepository.findByChoferIdOrderByFechaCreacionDesc(choferId);
        sincronizarConPedidos(rutas);
        return rutas.stream().map(this::mapearARutaResponse).collect(Collectors.toList());
    }

    @Override
    @Transactional
    public RutaResponse obtenerRutaPorId(UUID rutaId) {
        Ruta ruta = ruta(rutaId);
        sincronizarConPedidos(List.of(ruta));
        return mapearARutaResponse(ruta);
    }

    @Override
    @Transactional
    public List<DespachoResponse> listarDespachos() {
        sincronizarConPedidos(rutaRepository.findAllByOrderByFechaCreacionDesc());
        return despachoRepository.findAllByOrderByFechaAsignacionDesc().stream()
                .map(this::mapearADespachoResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public List<DespachoResponse> listarDespachosHoyChofer(UUID choferId) {
        sincronizarConPedidos(rutaRepository.findByChoferIdOrderByFechaCreacionDesc(choferId));
        return despachoRepository.findByChoferId(choferId).stream()
                .map(this::mapearADespachoResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public EvidenciaPodResponse obtenerEvidenciaPod(UUID despachoId) {
        Despacho d = despacho(despachoId);
        if (d.getEstado() != EstadoDespacho.ENTREGADO) {
            throw conflicto("La parada aún no ha sido entregada, por lo que no tiene prueba de entrega");
        }
        Chofer chofer = d.getChofer();
        return EvidenciaPodResponse.builder()
                .despachoId(d.getId())
                .cliente(d.getPedido().getCliente())
                .direccionCliente(d.getPedido().getDireccionTexto())
                .choferNombre(chofer != null ? chofer.getNombre() : null)
                .choferEmail(chofer != null ? chofer.getEmail() : null)
                .fotoPodUrl(d.getFotoPodUrl())
                .firmaUrl(d.getFirmaUrl())
                .latitudEntrega(GeometryUtil.extraerLatitud(d.getCoordenadaEntrega()))
                .longitudEntrega(GeometryUtil.extraerLongitud(d.getCoordenadaEntrega()))
                .latitudCliente(GeometryUtil.extraerLatitud(d.getPedido().getCoordenadaDestino()))
                .longitudCliente(GeometryUtil.extraerLongitud(d.getPedido().getCoordenadaDestino()))
                .desviacionMetros(d.getDesviacionMetros())
                .alertaDesviacion(d.getAlertaDesviacion())
                .fechaEntrega(d.getFechaEntrega())
                .comentarios(d.getComentarios())
                .build();
    }

    // =====================================================================
    // Operación del chofer en ruta
    // =====================================================================

    @Override
    @Transactional
    public DespachoResponse aceptarEIniciarRuta(UUID despachoId) {
        Despacho despacho = despacho(despachoId);
        if (despacho.getEstado() != EstadoDespacho.PENDIENTE) {
            throw conflicto("La parada no está pendiente");
        }
        Ruta ruta = despacho.getRuta();
        Chofer chofer = despacho.getChofer() != null ? despacho.getChofer() : ruta != null ? ruta.getChofer() : null;
        if (chofer == null) throw conflicto("La parada no tiene chofer asignado");
        if (ruta != null && ruta.getEstado() == EstadoRuta.PENDIENTE && ocupado(chofer.getId(), ruta.getId())) {
            throw conflicto("Ya tienes otra ruta en curso; termínala antes de iniciar esta");
        }
        boolean otraEnCurso = despachoRepository.findByChoferId(chofer.getId()).stream()
                .anyMatch(d -> d.getEstado() == EstadoDespacho.EN_CURSO && !d.getId().equals(despachoId));
        if (otraEnCurso) {
            throw conflicto("Ya tienes una parada en curso. Entrégala o márcala como no entregada antes de iniciar otra.");
        }
        commercialBridge.lock(despachoId, true);
        despacho.setEstado(EstadoDespacho.EN_CURSO);
        despacho.setFechaInicioRuta(LocalDateTime.now());
        despacho.getPedido().setEstado(EstadoPedido.EN_RUTA);
        pedidoRepository.save(despacho.getPedido());
        chofer.setEstadoDisponibilidad(EstadoChofer.EN_RUTA);
        choferRepository.save(chofer);
        if (ruta != null && ruta.getEstado() == EstadoRuta.PENDIENTE) {
            ruta.setEstado(EstadoRuta.EN_CURSO);
            ruta.setFechaInicio(LocalDateTime.now());
            rutaRepository.save(ruta);
        }
        Despacho actualizado = despachoRepository.save(despacho);
        messagingTemplate.convertAndSend("/topic/despachos/" + despachoId + "/estado",
                Map.of("despachoId", despachoId.toString(), "estado", "EN_CURSO", "mensaje", "Parada iniciada por el chofer"));
        notificarActualizacionTablero();
        return mapearADespachoResponse(actualizado);
    }

    /** El chofer no pudo entregar: la parada queda "no entregada" y puede reintentarse mientras la ruta siga en curso. */
    @Override
    @Transactional
    public DespachoResponse cancelarRuta(UUID despachoId, String motivo) {
        Despacho despacho = despacho(despachoId);
        if (despacho.getEstado() == EstadoDespacho.ENTREGADO) {
            throw conflicto("No se puede cancelar una entrega ya completada");
        }
        despacho.setEstado(EstadoDespacho.CANCELADA);
        despacho.setComentarios(motivo != null && !motivo.isBlank() ? "No entregado: " + motivo.trim() : "No entregado");
        despacho.getPedido().setEstado(EstadoPedido.CANCELADO);
        pedidoRepository.save(despacho.getPedido());
        Despacho actualizado = despachoRepository.save(despacho);

        Ruta ruta = despacho.getRuta();
        if (ruta != null) {
            try {
                optimizarRutaPorChofer(ruta.getId(),
                        GeometryUtil.extraerLatitud(despacho.getPedido().getCoordenadaDestino()),
                        GeometryUtil.extraerLongitud(despacho.getPedido().getCoordenadaDestino()));
            } catch (Exception e) {
                log.warn("No se pudo reoptimizar la ruta tras la cancelación: {}", e.getMessage());
            }
            cerrarRutaSiTermino(ruta);
        }
        messagingTemplate.convertAndSend("/topic/despachos/" + despachoId + "/estado",
                Map.of("despachoId", despachoId.toString(), "estado", "CANCELADA", "mensaje", "Parada no entregada"));
        notificarActualizacionTablero();
        return mapearADespachoResponse(actualizado);
    }

    @Override
    @Transactional
    public DespachoResponse cerrarEntrega(UUID despachoId, CerrarEntregaRequest request) {
        Despacho despacho = despacho(despachoId);
        if (despacho.getEstado() == EstadoDespacho.ENTREGADO) {
            return mapearADespachoResponse(despacho);
        }
        if (request.getFotoPodUrl() == null || request.getFotoPodUrl().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La foto de la entrega es obligatoria");
        }
        if (request.getFirmaUrl() == null || request.getFirmaUrl().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La firma del receptor es obligatoria");
        }
        if (request.getLatitud() == null || request.getLongitud() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La ubicación GPS de la entrega es obligatoria");
        }
        commercialBridge.lock(despachoId, false);

        Point puntoEntrega = GeometryUtil.crearPunto(request.getLatitud(), request.getLongitud());
        despacho.setCoordenadaEntrega(puntoEntrega);
        despacho.setFotoPodUrl(request.getFotoPodUrl());
        despacho.setFirmaUrl(request.getFirmaUrl());
        despacho.setFechaEntrega(LocalDateTime.now());
        despacho.setComentarios(request.getComentarios());

        double distancia = GeoDistanceCalculator.calcularDistanciaPuntos(puntoEntrega, despacho.getPedido().getCoordenadaDestino());
        despacho.setDesviacionMetros(distancia);
        despacho.setAlertaDesviacion(distancia > UMBRAL_ALERTA_DESVIACION_METROS);

        // Pedidos registra la entrega y mueve la custodia del material.
        commercialBridge.delivered(despachoId);
        despacho.setEstado(EstadoDespacho.ENTREGADO);
        despacho.getPedido().setEstado(EstadoPedido.ENTREGADO);
        pedidoRepository.save(despacho.getPedido());
        Despacho guardado = despachoRepository.save(despacho);

        cerrarRutaSiTermino(despacho.getRuta());
        messagingTemplate.convertAndSend("/topic/despachos/" + despachoId + "/estado",
                Map.of("despachoId", despachoId.toString(), "estado", "ENTREGADO", "mensaje", "Entrega completada"));
        notificarActualizacionTablero();
        return mapearADespachoResponse(guardado);
    }

    @Override
    @Transactional
    public DespachoResponse reintentarParada(UUID despachoId) {
        Despacho despacho = despacho(despachoId);
        if (despacho.getEstado() != EstadoDespacho.CANCELADA) {
            throw conflicto("Solo se reintenta una parada no entregada");
        }
        Ruta ruta = despacho.getRuta();
        if (ruta == null || ruta.getEstado() != EstadoRuta.EN_CURSO) {
            throw conflicto("La ruta ya se cerró; el material de esta parada debe volver a bodega");
        }
        String estadoEnvio = commercialBridge.estados(List.of(despachoId)).get(despachoId);
        if (estadoEnvio != null && !"EN_REPARTO".equals(estadoEnvio)) {
            throw conflicto("El pedido fue cancelado o venció; no se puede reintentar la entrega");
        }
        despacho.setEstado(EstadoDespacho.PENDIENTE);
        despacho.setComentarios(null);
        despacho.getPedido().setEstado(EstadoPedido.PENDIENTE);
        pedidoRepository.save(despacho.getPedido());
        Despacho guardado = despachoRepository.save(despacho);
        avisarChofer(ruta);
        notificarActualizacionTablero();
        return mapearADespachoResponse(guardado);
    }

    @Override
    @Transactional
    public RutaResponse optimizarRutaPorChofer(UUID rutaId, Double latChofer, Double lonChofer) {
        Ruta ruta = ruta(rutaId);
        List<Despacho> paradas = ruta.getParadas();
        if (paradas.size() <= 1) return mapearARutaResponse(ruta);

        List<Despacho> finalizadas = paradas.stream()
                .filter(d -> FINALES.contains(d.getEstado()))
                .sorted(Comparator.comparing(Despacho::getOrdenParada))
                .collect(Collectors.toList());
        List<Despacho> pendientes = paradas.stream()
                .filter(d -> !FINALES.contains(d.getEstado()))
                .collect(Collectors.toList());
        if (pendientes.size() <= 1) return mapearARutaResponse(ruta);

        double origenLat = latChofer != null ? latChofer : LAT_BODEGA_QUITO;
        double origenLon = lonChofer != null ? lonChofer : LON_BODEGA_QUITO;
        List<Pedido> optimizados = ordenarPedidosPorProximidad(
                pendientes.stream().map(Despacho::getPedido).collect(Collectors.toList()), origenLat, origenLon);

        int orden = finalizadas.size() + 1;
        for (Pedido p : optimizados) {
            for (Despacho d : pendientes) {
                if (d.getPedido().getId().equals(p.getId())) {
                    d.setOrdenParada(orden++);
                    break;
                }
            }
        }
        paradas.sort(Comparator.comparing(Despacho::getOrdenParada));
        rutaRepository.save(ruta);
        avisarChofer(ruta);
        notificarActualizacionTablero();
        return mapearARutaResponse(ruta);
    }

    /** Vecino más cercano según duraciones viales (Google Routes, con respaldo OSRM/Haversine). */
    private List<Pedido> ordenarPedidosPorProximidad(List<Pedido> pedidos, double latOrigen, double lonOrigen) {
        if (pedidos == null || pedidos.size() <= 1) {
            return pedidos != null ? new ArrayList<>(pedidos) : new ArrayList<>();
        }
        List<double[]> coordenadas = new ArrayList<>();
        coordenadas.add(new double[]{latOrigen, lonOrigen});
        List<Pedido> validos = new ArrayList<>();
        for (Pedido p : pedidos) {
            Double lat = GeometryUtil.extraerLatitud(p.getCoordenadaDestino());
            Double lon = GeometryUtil.extraerLongitud(p.getCoordenadaDestino());
            if (lat != null && lon != null) {
                coordenadas.add(new double[]{lat, lon});
                validos.add(p);
            }
        }
        if (validos.size() <= 1) return validos;

        double[][] duraciones = googleRoutesService.obtenerMatrizDuracionesViales(coordenadas);
        int total = coordenadas.size();
        boolean[] visitados = new boolean[total];
        visitados[0] = true;
        List<Pedido> resultado = new ArrayList<>();
        int actual = 0;
        for (int paso = 0; paso < validos.size(); paso++) {
            int mejor = -1;
            double menor = Double.MAX_VALUE;
            for (int c = 1; c < total; c++) {
                if (!visitados[c] && duraciones[actual][c] < menor) {
                    menor = duraciones[actual][c];
                    mejor = c;
                }
            }
            if (mejor == -1) {
                for (int c = 1; c < total; c++) {
                    if (!visitados[c]) { mejor = c; break; }
                }
            }
            visitados[mejor] = true;
            resultado.add(validos.get(mejor - 1));
            actual = mejor;
        }
        return resultado;
    }

    // =====================================================================
    // Propiedad
    // =====================================================================

    @Override
    @Transactional(readOnly = true)
    public UUID choferDeRuta(UUID rutaId) {
        Ruta r = ruta(rutaId);
        return r.getChofer() != null ? r.getChofer().getId() : null;
    }

    @Override
    @Transactional(readOnly = true)
    public UUID choferDeDespacho(UUID despachoId) {
        Despacho d = despacho(despachoId);
        if (d.getChofer() != null) return d.getChofer().getId();
        return d.getRuta() != null && d.getRuta().getChofer() != null ? d.getRuta().getChofer().getId() : null;
    }

    // =====================================================================
    // Mapeo
    // =====================================================================

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
        if (c == null) return null;
        return ChoferResponse.builder()
                .id(c.getId())
                .nombre(c.getNombre())
                .email(c.getEmail())
                .telefono(c.getTelefono())
                .estadoDisponibilidad(c.getEstadoDisponibilidad())
                .createdAt(c.getCreatedAt())
                .build();
    }

    private List<Map<String, Object>> carga(Despacho d) {
        if (d.getCarga() == null || d.getCarga().isBlank()) return List.of();
        try {
            return json.readValue(d.getCarga(), new TypeReference<List<Map<String, Object>>>() {});
        } catch (Exception e) {
            return List.of();
        }
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
                .pedidoComercialId(d.getPedidoComercialId())
                .numeroPedido(d.getNumeroPedido())
                .envioComercialId(d.getEnvioComercialId())
                .carga(carga(d))
                .build();
    }

    private RutaResponse mapearARutaResponse(Ruta r) {
        List<DespachoResponse> paradas = r.getParadas().stream()
                .sorted(Comparator.comparing(Despacho::getOrdenParada, Comparator.nullsLast(Comparator.naturalOrder())))
                .map(this::mapearADespachoResponse)
                .collect(Collectors.toList());
        return RutaResponse.builder()
                .id(r.getId())
                .codigoRuta(r.getCodigoRuta())
                .choferId(r.getChofer() != null ? r.getChofer().getId() : null)
                .choferNombre(r.getChofer() != null ? r.getChofer().getNombre() : null)
                .choferTelefono(r.getChofer() != null ? r.getChofer().getTelefono() : null)
                .estado(r.getEstado())
                .fechaCreacion(r.getFechaCreacion())
                .fechaInicio(r.getFechaInicio())
                .fechaFin(r.getFechaFin())
                .comentarios(r.getComentarios())
                .paradas(paradas)
                .build();
    }
}
