package com.titulacionammo.glassflow.auth.dto;

import com.titulacionammo.glassflow.auth.model.RolUsuario;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

/**
 * Objeto para creacion de nuevos usuarios por parte del Administrador.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CrearUsuarioRequest {

    /**
     * Identificador UUID opcional para coordinar el perfil con otros microservicios.
     */
    private UUID id;

    @NotBlank(message = "El correo electronico es obligatorio.")
    @Email(message = "El formato de correo electronico es invalido.")
    private String email;

    @NotBlank(message = "La contrasena es obligatoria.")
    @Size(min = 6, message = "La contrasena debe contener al menos 6 caracteres.")
    private String password;

    @NotBlank(message = "El nombre completo es obligatorio.")
    private String nombre;

    private String telefono;

    @NotNull(message = "El rol de usuario es obligatorio.")
    private RolUsuario rol;
}
