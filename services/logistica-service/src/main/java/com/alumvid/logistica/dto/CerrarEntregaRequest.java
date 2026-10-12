package com.alumvid.logistica.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CerrarEntregaRequest {

    @NotBlank(message = "La evidencia fotografica (PoD) es obligatoria.")
    private String fotoPodUrl;

    @NotBlank(message = "La firma digital tactil del cliente es obligatoria.")
    private String firmaUrl;

    @NotNull(message = "La latitud de captura GPS es obligatoria.")
    private Double latitud;

    @NotNull(message = "La longitud de captura GPS es obligatoria.")
    private Double longitud;

    private String comentarios;
}
