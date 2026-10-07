package com.titulacionammo.glassflow.auth.security;

import io.github.bucket4j.Bandwidth;
import io.github.bucket4j.Bucket;
import io.github.bucket4j.Refill;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Filtro de seguridad para prevencion de ataques de fuerza bruta y denegacion de servicio (DoS)
 * utilizando el algoritmo Token Bucket de Bucket4j.
 */
@Component
public class RateLimitingFilter extends OncePerRequestFilter {

    private final Map<String, Bucket> bucketsPorIp = new ConcurrentHashMap<>();
    private final long capacity;
    private final long tokensPerMinute;

    public RateLimitingFilter(
            @Value("${glassflow.security.rate-limit.capacity:10}") long capacity,
            @Value("${glassflow.security.rate-limit.tokens-per-minute:10}") long tokensPerMinute) {
        this.capacity = capacity;
        this.tokensPerMinute = tokensPerMinute;
    }

    private Bucket crearNuevoBucket() {
        Bandwidth limit = Bandwidth.classic(capacity, Refill.intervally(tokensPerMinute, Duration.ofMinutes(1)));
        return Bucket.builder().addLimit(limit).build();
    }

    private Bucket obtenerBucket(String ip) {
        return bucketsPorIp.computeIfAbsent(ip, k -> crearNuevoBucket());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        // Aplicar rate limiting de forma prioritaria al endpoint de inicio de sesion
        if ("POST".equalsIgnoreCase(request.getMethod()) && request.getRequestURI().endsWith("/auth/login")) {
            String clientIp = extraerIpCliente(request);
            Bucket bucket = obtenerBucket(clientIp);

            if (!bucket.tryConsume(1)) {
                response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
                response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                response.getWriter().write(
                        "{\"error\":\"Limite de peticiones excedido. Espere un minuto antes de intentar nuevamente.\",\"status\":429}"
                );
                return;
            }
        }

        filterChain.doFilter(request, response);
    }

    private String extraerIpCliente(HttpServletRequest request) {
        String xfHeader = request.getHeader("X-Forwarded-For");
        if (xfHeader == null || xfHeader.isEmpty()) {
            return request.getRemoteAddr();
        }
        return xfHeader.split(",")[0].trim();
    }
}
