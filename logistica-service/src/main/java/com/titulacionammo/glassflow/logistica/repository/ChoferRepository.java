package com.titulacionammo.glassflow.logistica.repository;

import com.titulacionammo.glassflow.logistica.model.Chofer;
import com.titulacionammo.glassflow.logistica.model.EstadoChofer;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface ChoferRepository extends JpaRepository<Chofer, UUID> {

    Optional<Chofer> findByEmail(String email);

    List<Chofer> findByEstadoDisponibilidad(EstadoChofer estado);
}
