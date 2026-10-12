package com.alumvid.usuarios;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.Set;
import java.util.UUID;

@Service
public class JwtService {

    private final SecretKey signingKey;
    private final long expirationTimeMs;

    public JwtService(
            @Value("${alumvid.security.jwt.secret:c3VwZXJfc2VjcmV0X2tleV9hbHVtdmlkXzIwMjZfand0X3NpZ25hdHVyZV9obWFj=}") String secret,
            @Value("${alumvid.security.jwt.expiration-hours:24}") long expirationHours) {
        this.signingKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expirationTimeMs = expirationHours * 3600 * 1000;
    }

    public String generarToken(Users.User user) {
        Date ahora = new Date();
        Date fechaExpiracion = new Date(ahora.getTime() + expirationTimeMs);

        String primaryRole = "ROLE_OPERARIO";
        if (user.roles().contains(Users.Role.ADMINISTRADOR)) {
            primaryRole = "ROLE_ADMIN";
        } else if (user.roles().contains(Users.Role.CHOFER)) {
            primaryRole = "ROLE_CHOFER";
        }

        String emailVal = user.email() != null && !user.email().isBlank()
                ? user.email()
                : user.identification() + "@alumvid.com";

        return Jwts.builder()
                .subject(user.identification())
                .claim("userId", user.id().toString())
                .claim("identification", user.identification())
                .claim("email", emailVal)
                .claim("nombre", user.fullName())
                .claim("roles", Users.encode(user.roles()))
                .claim("rol", primaryRole)
                .claim("master", user.master())
                .claim("mustChangePassword", user.mustChangePassword())
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

    public String extraerIdentificacion(String token) {
        return extraerClaims(token).getSubject();
    }

    public UUID extraerUserId(String token) {
        return UUID.fromString(extraerClaims(token).get("userId", String.class));
    }

    public Claims extraerClaims(String token) {
        return Jwts.parser()
                .verifyWith(signingKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    public long getExpirationTimeMs() {
        return expirationTimeMs;
    }
}
