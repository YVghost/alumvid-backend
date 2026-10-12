package com.alumvid.usuarios;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

@Configuration
@EnableWebSecurity
public class Security {

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    public static String hash(String value) {
        try {
            var md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(value.getBytes(StandardCharsets.UTF_8));
            var sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http, AuthFilter authFilter) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers(
                    "/",
                    "/index.html",
                    "/style.css",
                    "/app.js",
                    "/favicon.ico",
                    "/actuator/**",
                    "/api/auth/login",
                    "/api/v1/auth/login",
                    "/api/auth/register",
                    "/api/v1/auth/register"
                ).permitAll()
                .anyRequest().authenticated()
            )
            .addFilterBefore(authFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOriginPatterns(List.of("*"));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);
        config.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }

    @Bean
    public AuthFilter authFilter(Users users, JwtService jwtService) {
        return new AuthFilter(users, jwtService);
    }

    public static class AuthFilter extends OncePerRequestFilter {
        private final Users users;
        private final JwtService jwtService;

        public AuthFilter(Users users, JwtService jwtService) {
            this.users = users;
            this.jwtService = jwtService;
        }

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
                throws ServletException, IOException {
            String header = request.getHeader("Authorization");
            if (header != null && header.startsWith("Bearer ")) {
                String token = header.substring(7).trim();
                try {
                    Users.User user = null;

                    // 1. Intento validacion JWT
                    if (jwtService.esTokenValido(token)) {
                        String idStr = jwtService.extraerIdentificacion(token);
                        user = users.byIdentification(idStr).orElse(null);
                    }

                    // 2. Intento de respaldo con sesion SHA-256 (para clientes basados en sesion de base de datos)
                    if (user == null) {
                        String tokenHash = Security.hash(token);
                        List<UUID> userIds = users.db().query(
                            "SELECT user_id FROM usuarios.auth_session WHERE token_hash = ? AND expires_at > CURRENT_TIMESTAMP",
                            (rs, rowNum) -> rs.getObject("user_id", UUID.class),
                            tokenHash
                        );
                        if (!userIds.isEmpty()) {
                            user = users.byId(userIds.get(0));
                        }
                    }

                    if (user != null && user.active()) {
                        List<SimpleGrantedAuthority> authorities = new ArrayList<>();
                        for (Users.Role r : user.roles()) {
                            authorities.add(new SimpleGrantedAuthority(r.name()));
                            authorities.add(new SimpleGrantedAuthority("ROLE_" + r.name()));
                        }
                        if (user.roles().contains(Users.Role.ADMINISTRADOR)) {
                            authorities.add(new SimpleGrantedAuthority("ROLE_ADMIN"));
                        }
                        if (user.roles().contains(Users.Role.CHOFER)) {
                            authorities.add(new SimpleGrantedAuthority("ROLE_CHOFER"));
                        }
                        if (user.roles().contains(Users.Role.BODEGUERO)) {
                            authorities.add(new SimpleGrantedAuthority("ROLE_OPERARIO"));
                        }

                        var auth = new UsernamePasswordAuthenticationToken(user, null, authorities);
                        SecurityContextHolder.getContext().setAuthentication(auth);
                    }
                } catch (Exception ignored) {
                    // Si el token es invalido no se establece autenticacion
                }
            }
            filterChain.doFilter(request, response);
        }
    }
}
