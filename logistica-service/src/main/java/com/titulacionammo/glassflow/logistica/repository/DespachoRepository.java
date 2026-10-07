package com.titulacionammo.glassflow.logistica.repository;

import com.titulacionammo.glassflow.logistica.model.Despacho;
import com.titulacionammo.glassflow.logistica.model.EstadoDespacho;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface DespachoRepository extends JpaRepository<Despacho, UUID> {

    List<Despacho> findByChoferIdOrderByFechaAsignacionDesc(UUID choferId);

    List<Despacho> findByChoferId(UUID choferId);

    List<Despacho> findByRutaId(UUID rutaId);

    List<Despacho> findByChoferIdAndEstado(UUID choferId, EstadoDespacho estado);

    List<Despacho> findByEstado(EstadoDespacho estado);

    List<Despacho> findAllByOrderByFechaAsignacionDesc();

    Optional<Despacho> findByPedidoId(UUID pedidoId);

    /**
     * Consulta espacial nativa en PostGIS para calcular la distancia geodesica en metros
     * entre la coordenada de entrega y el destino oficial del cliente.
     */
    @Query(value = "SELECT ST_Distance(d.coordenada_entrega::geography, p.coordenada_destino::geography) " +
                   "FROM despachos d " +
                   "JOIN pedidos p ON d.pedido_id = p.id " +
                   "WHERE d.id = :despachoId", nativeQuery = true)
    Double calcularDistanciaEntregaPostGIS(@Param("despachoId") UUID despachoId);
}
