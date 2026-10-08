package com.titulacionammo.glassflow.auth.service;

import com.titulacionammo.glassflow.auth.dto.*;
import com.titulacionammo.glassflow.auth.model.Usuario;
import com.titulacionammo.glassflow.auth.repository.UsuarioRepository;
import com.titulacionammo.glassflow.auth.security.JwtService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Implementacion del servicio de autenticacion y gestion de usuarios.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class AuthServiceImpl implements AuthService {

    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;

    @Override
    @Transactional(readOnly = true)
    public LoginResponse autenticar(LoginRequest request) {
        Usuario usuario = usuarioRepository.findByEmail(request.getEmail().toLowerCase().trim())
                .orElseThrow(() -> new BadCredentialsException("Credenciales invalidas."));

        if (!Boolean.TRUE.equals(usuario.getActivo())) {
            throw new BadCredentialsException("La cuenta de usuario se encuentra suspendida.");
        }

        if (!passwordEncoder.matches(request.getPassword(), usuario.getPassword())) {
            throw new BadCredentialsException("Credenciales invalidas.");
        }

        String token = jwtService.generarToken(usuario);

        return LoginResponse.builder()
                .token(token)
                .tipoToken("Bearer")
                .id(usuario.getId())
                .email(usuario.getEmail())
                .nombre(usuario.getNombre())
                .rol(usuario.getRol())
                .expiresInMs(jwtService.getExpirationTimeMs())
                .build();
    }

    @Override
    @Transactional
    public UsuarioResponse crearUsuario(CrearUsuarioRequest request) {
        String emailNormalizado = request.getEmail().toLowerCase().trim();

        if (usuarioRepository.existsByEmail(emailNormalizado)) {
            throw new IllegalArgumentException("Ya existe un usuario registrado con el correo electronico especificado.");
        }

        Usuario usuario = Usuario.builder()
                .id(request.getId()) // Permite sincronizar UUID con perfil logistico si se proporciona
                .email(emailNormalizado)
                .password(passwordEncoder.encode(request.getPassword()))
                .nombre(request.getNombre().trim())
                .telefono(request.getTelefono() != null ? request.getTelefono().trim() : null)
                .rol(request.getRol())
                .activo(true)
                .build();

        Usuario guardado = usuarioRepository.save(usuario);
        log.info("Usuario creado exitosamente: {} con rol: {}", guardado.getEmail(), guardado.getRol());

        return mapearAUsuarioResponse(guardado);
    }

    @Override
    @Transactional(readOnly = true)
    public List<UsuarioResponse> listarUsuarios() {
        return usuarioRepository.findAll().stream()
                .map(this::mapearAUsuarioResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public UsuarioResponse obtenerPorId(UUID id) {
        Usuario usuario = usuarioRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado con ID: " + id));
        return mapearAUsuarioResponse(usuario);
    }

    @Override
    @Transactional
    public UsuarioResponse actualizarEstado(UUID id, boolean activo) {
        Usuario usuario = usuarioRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado con ID: " + id));

        usuario.setActivo(activo);
        Usuario actualizado = usuarioRepository.save(usuario);
        log.info("Estado del usuario {} actualizado a activo={}", usuario.getEmail(), activo);

        return mapearAUsuarioResponse(actualizado);
    }

    @Override
    @Transactional(readOnly = true)
    public UsuarioResponse obtenerPerfilActual(String email) {
        Usuario usuario = usuarioRepository.findByEmail(email.toLowerCase().trim())
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado con correo: " + email));
        return mapearAUsuarioResponse(usuario);
    }

    @Override
    @Transactional
    public void eliminarUsuario(UUID id) {
        Usuario usuario = usuarioRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado con ID: " + id));

        if ("admin@glassflow.com".equalsIgnoreCase(usuario.getEmail().trim())) {
            throw new IllegalArgumentException("La cuenta principal de Administrador no puede ser eliminada.");
        }

        usuarioRepository.delete(usuario);
        log.info("Usuario {} ({}) eliminado permanentemente del sistema.", usuario.getEmail(), id);
    }

    private UsuarioResponse mapearAUsuarioResponse(Usuario u) {
        return UsuarioResponse.builder()
                .id(u.getId())
                .email(u.getEmail())
                .nombre(u.getNombre())
                .telefono(u.getTelefono())
                .rol(u.getRol())
                .activo(u.getActivo())
                .createdAt(u.getCreatedAt())
                .build();
    }
}
