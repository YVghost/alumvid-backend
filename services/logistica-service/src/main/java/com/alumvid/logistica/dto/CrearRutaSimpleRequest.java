package com.alumvid.logistica.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CrearRutaSimpleRequest {
    @NotBlank(message = "El nombre o codigo de la ruta es obligatorio")
    private String codigoRuta;
    private UUID choferId;
    private String comentarios;
}
