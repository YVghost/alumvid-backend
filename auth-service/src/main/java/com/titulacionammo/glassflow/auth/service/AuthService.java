package com.titulacionammo.glassflow.auth.service;

import com.titulacionammo.glassflow.auth.dto.*;

import java.util.List;
import java.util.UUID;

/**
 * Contrato de servicios para autenticacion y administracion de usuarios.
 */
public interface AuthService {

    LoginResponse autenticar(LoginRequest request);

    UsuarioResponse crearUsuario(CrearUsuarioRequest request);

    List<UsuarioResponse> listarUsuarios();

    UsuarioResponse obtenerPorId(UUID id);

    UsuarioResponse actualizarEstado(UUID id, boolean activo);

    UsuarioResponse obtenerPerfilActual(String email);

    void eliminarUsuario(UUID id);
}
