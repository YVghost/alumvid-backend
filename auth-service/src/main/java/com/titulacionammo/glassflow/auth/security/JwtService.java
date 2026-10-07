package com.titulacionammo.glassflow.auth.security;

import com.titulacionammo.glassflow.auth.model.Usuario;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.UUID;

/**
 * Servicio criptografico para generacion y validacion de tokens JWT con algoritmo HMAC-SHA256.
 */
@Service
public class JwtService {

    private final SecretKey signingKey;
    private final long expirationTimeMs;

    public JwtService(
            @Value("${glassflow.security.jwt.secret:c3VwZXJfc2VjcmV0X2tleV9nbGFzc2Zsb3dfMjAyNl9qd3Rfc2lnbmF0dXJlX2htYWM=}") String secret,
            @Value("${glassflow.security.jwt.expiration-hours:24}") long expirationHours) {
        this.signingKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expirationTimeMs = expirationHours * 3600 * 1000;
    }

    public String generarToken(Usuario usuario) {
        Date ahora = new Date();
        Date fechaExpiracion = new Date(ahora.getTime() + expirationTimeMs);

        return Jwts.builder()
                .subject(usuario.getEmail())
                .claim("userId", usuario.getId().toString())
                .claim("nombre", usuario.getNombre())
                .claim("rol", usuario.getRol().name())
                .issuedAt(ahora)
                .expiration(fechaExpiracion)
                .signWith(signingKey)
                .compact();
    }

    public boolean esTokenValido(String token) {
        try {
            Claims claims = extraerClaims(token);
            return !claims.getExpiration().before(new Date());
        } catch (Exception e) {
            return false;
        }
    }

    public String extraerEmail(String token) {
        return extraerClaims(token).getSubject();
    }

    public String extraerRol(String token) {
        return extraerClaims(token).get("rol", String.class);
    }

    public UUID extraerUserId(String token) {
        return UUID.fromString(extraerClaims(token).get("userId", String.class));
    }

    public long getExpirationTimeMs() {
        return expirationTimeMs;
    }

    private Claims extraerClaims(String token) {
        return Jwts.parser()
                .verifyWith(signingKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
}
