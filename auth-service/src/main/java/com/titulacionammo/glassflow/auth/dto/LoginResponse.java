package com.titulacionammo.glassflow.auth.dto;

import com.titulacionammo.glassflow.auth.model.RolUsuario;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

/**
 * Respuesta devuelta tras una autenticacion exitosa con token JWT.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class LoginResponse {

    private String token;
    private String tipoToken;
    private UUID id;
    private String email;
    private String nombre;
    private RolUsuario rol;
    private Long expiresInMs;
}
