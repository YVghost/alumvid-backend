package com.alumvid.logistica.repository;

import com.alumvid.logistica.model.EstadoRuta;
import com.alumvid.logistica.model.Ruta;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface RutaRepository extends JpaRepository<Ruta, UUID> {
    List<Ruta> findAllByOrderByFechaCreacionDesc();
    List<Ruta> findByChoferIdOrderByFechaCreacionDesc(UUID choferId);
    List<Ruta> findByChoferIdAndEstadoIn(UUID choferId, List<EstadoRuta> estados);
    List<Ruta> findByEstado(EstadoRuta estado);
    boolean existsByCodigoRuta(String codigoRuta);
}
