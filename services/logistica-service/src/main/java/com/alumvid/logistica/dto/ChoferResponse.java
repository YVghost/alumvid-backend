package com.alumvid.logistica.dto;

import com.alumvid.logistica.model.EstadoChofer;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ChoferResponse {

    private UUID id;
    private String nombre;
    private String email;
    private String telefono;
    private EstadoChofer estadoDisponibilidad;
    private LocalDateTime createdAt;
}
