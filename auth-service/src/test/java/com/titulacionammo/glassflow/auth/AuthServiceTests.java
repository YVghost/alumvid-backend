package com.titulacionammo.glassflow.auth;

import com.titulacionammo.glassflow.auth.dto.CrearUsuarioRequest;
import com.titulacionammo.glassflow.auth.dto.LoginRequest;
import com.titulacionammo.glassflow.auth.dto.LoginResponse;
import com.titulacionammo.glassflow.auth.dto.UsuarioResponse;
import com.titulacionammo.glassflow.auth.model.RolUsuario;
import com.titulacionammo.glassflow.auth.service.AuthService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@Transactional
class AuthServiceTests {

    @Autowired
    private AuthService authService;

    @Test
    @DisplayName("Autenticacion exitosa de usuario y generacion de token JWT")
    void testAutenticacionExitosa() {
        authService.crearUsuario(CrearUsuarioRequest.builder()
                .email("test.admin@glassflow.com")
                .password("PasswordSegura2026!")
                .nombre("Usuario Test")
                .rol(RolUsuario.ROLE_ADMIN)
                .build());

        LoginResponse response = authService.autenticar(LoginRequest.builder()
                .email("test.admin@glassflow.com")
                .password("PasswordSegura2026!")
                .build());

        assertNotNull(response.getToken());
        assertEquals("test.admin@glassflow.com", response.getEmail());
        assertEquals(RolUsuario.ROLE_ADMIN, response.getRol());
    }

    @Test
    @DisplayName("Rechazo de autenticacion con credenciales invalidas")
    void testRechazoCredencialesInvalidas() {
        assertThrows(BadCredentialsException.class, () ->
                authService.autenticar(LoginRequest.builder()
                        .email("inexistente@glassflow.com")
                        .password("clave_erronea")
                        .build())
        );
    }

    @Test
    @DisplayName("Creacion de chofer por administrador y validacion de unicidad de correo")
    void testCreacionChoferYUnicidad() {
        UsuarioResponse creado = authService.crearUsuario(CrearUsuarioRequest.builder()
                .email("chofer.unico@glassflow.com")
                .password("ChoferPass2026!")
                .nombre("Chofer Unico")
                .telefono("+593988776655")
                .rol(RolUsuario.ROLE_CHOFER)
                .build());

        assertNotNull(creado.getId());
        assertEquals(RolUsuario.ROLE_CHOFER, creado.getRol());

        assertThrows(IllegalArgumentException.class, () ->
                authService.crearUsuario(CrearUsuarioRequest.builder()
                        .email("chofer.unico@glassflow.com")
                        .password("OtraClave2026!")
                        .nombre("Duplicado")
                        .rol(RolUsuario.ROLE_CHOFER)
                        .build())
        );
    }
}
