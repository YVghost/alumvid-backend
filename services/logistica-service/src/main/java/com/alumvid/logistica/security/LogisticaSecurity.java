package com.alumvid.logistica.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.server.ResponseStatusException;

/**
 * Logística exige sesión válida. Planificación de rutas: ADMINISTRADOR.
 * Operación en ruta (iniciar, entregar, cancelar parada, GPS): CHOFER dueño o ADMINISTRADOR.
 */
@Configuration
public class LogisticaSecurity {
    private static final String API = "/api/v1/logistica";

    @Bean
    SecurityFilterChain logisticaChain(HttpSecurity http, AuthClient auth) throws Exception {
        var filter = new OncePerRequestFilter() {
            @Override
            protected boolean shouldNotFilter(HttpServletRequest r) {
                String uri = r.getRequestURI();
                return !uri.startsWith("/api/") || uri.equals(API + "/health") || "OPTIONS".equals(r.getMethod());
            }

            @Override
            protected void doFilterInternal(HttpServletRequest q, HttpServletResponse r, FilterChain chain) throws IOException, ServletException {
                String token = q.getHeader("Authorization");
                if (token == null || !token.startsWith("Bearer ")) { fail(r, 401, "Debes iniciar sesión"); return; }
                try {
                    var actor = auth.identity(token);
                    if (actor.mustChangePassword()) { fail(r, 403, "Debes cambiar la clave temporal"); return; }
                    var roles = actor.roles().stream().map(role -> new SimpleGrantedAuthority("ROLE_" + role)).toList();
                    SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(actor, token, roles));
                } catch (ResponseStatusException e) {
                    fail(r, e.getStatusCode().value(), e.getReason());
                    return;
                }
                chain.doFilter(q, r);
            }
        };
        return http.csrf(c -> c.disable())
                .cors(c -> {})
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(a -> a
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .requestMatchers(API + "/health", "/ws-logistica/**", "/ws-telemetria/**", "/actuator/health").permitAll()
                        // Operación del chofer en ruta (la propiedad se valida en el controlador).
                        .requestMatchers(HttpMethod.GET, API + "/choferes/*/rutas", API + "/choferes/*/despachos-hoy", API + "/rutas/*").hasAnyRole("ADMINISTRADOR", "CHOFER")
                        .requestMatchers(HttpMethod.POST, API + "/despachos/*/aceptar-inicio", API + "/despachos/*/cancelar",
                                API + "/despachos/*/reintentar", API + "/despachos/*/cerrar-entrega",
                                API + "/rutas/*/optimizar-chofer", API + "/telemetria").hasAnyRole("ADMINISTRADOR", "CHOFER")
                        // Planificación y supervisión.
                        .requestMatchers(API + "/**").hasRole("ADMINISTRADOR")
                        .anyRequest().denyAll())
                .exceptionHandling(e -> e
                        .authenticationEntryPoint((q, r, x) -> fail(r, 401, "Debes iniciar sesión"))
                        .accessDeniedHandler((q, r, x) -> fail(r, 403, "Sin permisos para esta operación")))
                .addFilterBefore(filter, UsernamePasswordAuthenticationFilter.class)
                .build();
    }

    static void fail(HttpServletResponse r, int status, String message) throws IOException {
        r.setStatus(status);
        r.setContentType("application/json;charset=UTF-8");
        r.getWriter().write("{\"message\":\"" + (message == null ? "" : message.replace("\"", "'")) + "\"}");
    }
}
