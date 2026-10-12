package com.alumvid.logistica.repository;

import com.alumvid.logistica.model.EstadoPedido;
import com.alumvid.logistica.model.Pedido;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface PedidoRepository extends JpaRepository<Pedido, UUID> {

    List<Pedido> findByEstado(EstadoPedido estado);

    List<Pedido> findAllByOrderByFechaSolicitudDesc();
}
