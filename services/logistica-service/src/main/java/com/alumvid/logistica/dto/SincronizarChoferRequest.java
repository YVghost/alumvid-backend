package com.alumvid.logistica.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

/**
 * Peticion enviada desde el panel administrativo para registrar el chofer en el servicio logistico.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class SincronizarChoferRequest {

    @NotNull(message = "El identificador UUID es obligatorio.")
    private UUID id;

    @NotBlank(message = "El nombre es obligatorio.")
    private String nombre;

    @NotBlank(message = "El correo electronico es obligatorio.")
    @Email(message = "El formato de correo es invalido.")
    private String email;

    private String telefono;
}
