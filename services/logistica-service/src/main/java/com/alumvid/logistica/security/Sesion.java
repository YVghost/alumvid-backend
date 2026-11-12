package com.alumvid.logistica.security;

import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.server.ResponseStatusException;

/** Acceso al usuario autenticado de la petición en curso. */
public final class Sesion {
    private Sesion() {}

    public static AuthClient.Identity actor() {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof AuthClient.Identity actor)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Debes iniciar sesión");
        }
        return actor;
    }

    public static String token() {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getCredentials() instanceof String token)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Debes iniciar sesión");
        }
        return token;
    }

    /** Un chofer solo opera sus propias rutas; administración opera todas. */
    public static void exigirPropietario(UUID choferId) {
        var actor = actor();
        if (actor.admin()) return;
        if (choferId == null || !choferId.equals(actor.id())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Solo el chofer asignado o administración puede operar esta ruta");
        }
    }
}
