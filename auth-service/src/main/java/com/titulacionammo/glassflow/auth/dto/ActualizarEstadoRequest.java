package com.titulacionammo.glassflow.auth.dto;

import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Peticion para activar o suspender un usuario del sistema.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ActualizarEstadoRequest {

    @NotNull(message = "El estado activo es obligatorio.")
    private Boolean activo;
}
