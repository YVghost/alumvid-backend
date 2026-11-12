package com.alumvid.logistica.security;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

/** Valida sesiones contra usuarios-service (dueño de cuentas y roles). */
@Component
public class AuthClient {
    public record Identity(UUID id, String identification, String fullName, Set<String> roles,
                           boolean master, boolean active, boolean mustChangePassword) {
        public boolean has(String role) { return roles != null && roles.contains(role); }
        public boolean admin() { return has("ADMINISTRADOR"); }
    }

    private final RestClient client;

    public AuthClient(@Value("${AUTH_URL:http://localhost:8081}") String url) {
        var factory = new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build());
        factory.setReadTimeout(Duration.ofSeconds(4));
        client = RestClient.builder().baseUrl(url).requestFactory(factory).build();
    }

    public Identity identity(String authorization) {
        try {
            var identity = client.get().uri("/api/auth/me").header("Authorization", authorization).retrieve().body(Identity.class);
            if (identity == null || !identity.active()) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Sesión inválida");
            return identity;
        } catch (RestClientResponseException e) {
            int code = e.getStatusCode().value();
            if (code == 401 || code == 403) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Sesión inválida o vencida");
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "El servicio de usuarios no está disponible");
        } catch (RestClientException e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "El servicio de usuarios no está disponible");
        }
    }

    /** Choferes activos (rol CHOFER) según usuarios-service. */
    public List<Map<String, Object>> activeDrivers(String authorization) {
        try {
            var list = client.get().uri("/api/choferes").header("Authorization", authorization).retrieve()
                    .body(new ParameterizedTypeReference<List<Map<String, Object>>>() {});
            return list == null ? List.of() : list;
        } catch (RestClientException e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "No se pudo consultar los choferes en usuarios");
        }
    }
}
