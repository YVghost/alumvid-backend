package com.titulacionammo.glassflow.auth.controller;

import com.titulacionammo.glassflow.auth.dto.*;
import com.titulacionammo.glassflow.auth.service.AuthService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Controlador REST para operaciones de autenticacion y administracion de usuarios.
 */
@RestController
@RequestMapping("/api/v1/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> healthCheck() {
        return ResponseEntity.ok(Map.of("status", "UP", "service", "auth-service"));
    }

    @PostMapping("/login")
    public ResponseEntity<LoginResponse> login(@Valid @RequestBody LoginRequest request) {
        LoginResponse response = authService.autenticar(request);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/usuarios")
    @PreAuthorize("hasAuthority('ROLE_ADMIN')")
    public ResponseEntity<UsuarioResponse> crearUsuario(@Valid @RequestBody CrearUsuarioRequest request) {
        UsuarioResponse nuevoUsuario = authService.crearUsuario(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(nuevoUsuario);
    }

    @GetMapping("/usuarios")
    @PreAuthorize("hasAuthority('ROLE_ADMIN')")
    public ResponseEntity<List<UsuarioResponse>> listarUsuarios() {
        return ResponseEntity.ok(authService.listarUsuarios());
    }

    @GetMapping("/usuarios/{id}")
    @PreAuthorize("hasAuthority('ROLE_ADMIN')")
    public ResponseEntity<UsuarioResponse> obtenerPorId(@PathVariable UUID id) {
        return ResponseEntity.ok(authService.obtenerPorId(id));
    }

    @PatchMapping("/usuarios/{id}/estado")
    @PreAuthorize("hasAuthority('ROLE_ADMIN')")
    public ResponseEntity<UsuarioResponse> actualizarEstado(
            @PathVariable UUID id,
            @Valid @RequestBody ActualizarEstadoRequest request) {
        return ResponseEntity.ok(authService.actualizarEstado(id, request.getActivo()));
    }

    @GetMapping("/me")
    public ResponseEntity<UsuarioResponse> obtenerPerfilActual(Authentication authentication) {
        String email = authentication.getName();
        return ResponseEntity.ok(authService.obtenerPerfilActual(email));
    }
}
