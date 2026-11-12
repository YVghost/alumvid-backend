package com.alumvid.logistica.service;

import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

/**
 * Contrato con pedidos para la custodia del material en reparto.
 * Solo invoca las funciones que publica pedidos (lock/complete/cancel) y lee el
 * estado de los envíos; nunca escribe tablas de pedidos, inventario ni retazos.
 */
@Component
public class CommercialOrderBridge {
    private final JdbcTemplate db;

    public CommercialOrderBridge(JdbcTemplate db) {
        this.db = db;
    }

    private boolean ready() {
        return Boolean.TRUE.equals(db.queryForObject("SELECT to_regclass('pedidos.commercial_shipment') IS NOT NULL", Boolean.class));
    }

    private Optional<Map<String, Object>> envio(UUID dispatch) {
        if (!ready()) return Optional.empty();
        return db.queryForList("SELECT id,state,order_id FROM pedidos.commercial_shipment WHERE dispatch_id=?", dispatch).stream().findFirst();
    }

    /** Id del envío comercial vinculado a una parada (si existe). */
    public Optional<UUID> envioDe(UUID dispatch) {
        return envio(dispatch).map(e -> (UUID) e.get("id"));
    }

    /** Estado del envío comercial de cada parada (EN_REPARTO, ENTREGADO, RETORNO_PENDIENTE, DEVUELTO_BODEGA). */
    public Map<UUID, String> estados(Collection<UUID> dispatches) {
        if (dispatches.isEmpty() || !ready()) return Map.of();
        var result = new HashMap<UUID, String>();
        db.query("SELECT dispatch_id,state FROM pedidos.commercial_shipment WHERE dispatch_id = ANY(?)",
                ps -> ps.setArray(1, ps.getConnection().createArrayOf("uuid", dispatches.toArray())),
                rs -> { result.put((UUID) rs.getObject(1), rs.getString(2)); });
        return result;
    }

    public void lock(UUID dispatch, boolean checkOpen) {
        if (envio(dispatch).isEmpty()) return;
        db.queryForObject("SELECT pedidos.lock_commercial_dispatch(?)", UUID.class, dispatch);
        if (checkOpen) {
            var sale = db.queryForMap("SELECT o.state,o.expires_at>CURRENT_TIMESTAMP AS valid,s.state AS shipment_state FROM pedidos.sale_order o JOIN pedidos.commercial_shipment s ON s.order_id=o.id WHERE s.dispatch_id=?", dispatch);
            if (!Boolean.TRUE.equals(sale.get("valid")) || Set.of("CANCELADO", "VENCIDO", "RETRASADO").contains(sale.get("state")) || !"EN_REPARTO".equals(sale.get("shipment_state"))) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Pedido cerrado, retrasado o vencido; el material debe volver a bodega");
            }
        }
    }

    public void delivered(UUID dispatch) {
        if (envio(dispatch).isEmpty()) return;
        try {
            db.queryForObject("SELECT pedidos.complete_commercial_dispatch(?) IS NULL", Boolean.class, dispatch);
        } catch (org.springframework.dao.DataAccessException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "No se puede entregar: revisa el estado, vencimiento y custodia del pedido", e);
        }
    }

    /** El material salió con el chofer y no se entregó: queda pendiente su retorno a bodega. */
    public void cancelled(UUID dispatch, String reason) {
        var e = envio(dispatch);
        if (e.isPresent() && "EN_REPARTO".equals(e.get().get("state"))) {
            db.queryForObject("SELECT pedidos.cancel_commercial_dispatch(?,?) IS NULL", Boolean.class, dispatch, reason);
        }
    }

    public void route(UUID route, boolean open) {
        if (!ready()) return;
        for (var row : db.queryForList("SELECT dispatch_id FROM pedidos.commercial_shipment WHERE route_id=? AND state='EN_REPARTO' ORDER BY order_id,id", route)) {
            lock((UUID) row.get("dispatch_id"), open);
        }
    }
}
