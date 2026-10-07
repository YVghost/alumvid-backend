package com.titulacionammo.glassflow.auth.config;

import com.titulacionammo.glassflow.auth.dto.CrearUsuarioRequest;
import com.titulacionammo.glassflow.auth.model.RolUsuario;
import com.titulacionammo.glassflow.auth.repository.UsuarioRepository;
import com.titulacionammo.glassflow.auth.service.AuthService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

/**
 * Inicializador de datos semilla para asegurar la existencia del administrador inicial.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class AuthDataSeeder implements CommandLineRunner {

    private final UsuarioRepository usuarioRepository;
    private final AuthService authService;

    @Override
    public void run(String... args) {
        if (usuarioRepository.count() == 0) {
            log.info("Inicializando cuentas principales en el servicio de autenticacion...");

            // 1. Administrador general del sistema
            authService.crearUsuario(CrearUsuarioRequest.builder()
                    .email("admin@glassflow.com")
                    .password("GlassFlowAdmin2026!")
                    .nombre("Administrador de Operaciones")
                    .telefono("+593999999999")
                    .rol(RolUsuario.ROLE_ADMIN)
                    .build());

            // 2. Choferes iniciales de prueba
            authService.crearUsuario(CrearUsuarioRequest.builder()
                    .email("carlos.chofer@glassflow.com")
                    .password("ChoferPass2026!")
                    .nombre("Carlos Mosquera")
                    .telefono("+593987654321")
                    .rol(RolUsuario.ROLE_CHOFER)
                    .build());

            authService.crearUsuario(CrearUsuarioRequest.builder()
                    .email("mateo.chofer@glassflow.com")
                    .password("ChoferPass2026!")
                    .nombre("Mateo Ortega")
                    .telefono("+593991234567")
                    .rol(RolUsuario.ROLE_CHOFER)
                    .build());

            log.info("Cuentas iniciales registradas exitosamente.");
        }
    }
}
