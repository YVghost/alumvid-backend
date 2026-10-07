package com.titulacionammo.glassflow.auth.dto;

import com.titulacionammo.glassflow.auth.model.RolUsuario;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Representacion publica de un usuario registrado en el sistema.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UsuarioResponse {

    private UUID id;
    private String email;
    private String nombre;
    private String telefono;
    private RolUsuario rol;
    private Boolean activo;
    private LocalDateTime createdAt;
}
