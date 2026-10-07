package com.titulacionammo.glassflow.logistica.dto;

import com.titulacionammo.glassflow.logistica.model.EstadoRuta;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RutaResponse {

    private UUID id;
    private String codigoRuta;
    private UUID choferId;
    private String choferNombre;
    private String choferTelefono;
    private EstadoRuta estado;
    private LocalDateTime fechaCreacion;
    private LocalDateTime fechaInicio;
    private LocalDateTime fechaFin;
    private String comentarios;

    @Builder.Default
    private List<DespachoResponse> paradas = new ArrayList<>();
}
