package com.vidrios.usuarios;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.context.annotation.*;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.filter.OncePerRequestFilter;

@Configuration
class Security {
    static String hash(String token) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8))); }
        catch (NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
    @Bean PasswordEncoder passwords() { return new BCryptPasswordEncoder(); }
    @Bean TokenFilter tokens(Users users) { return new TokenFilter(users); }
    @Bean FilterRegistrationBean<TokenFilter> registration(TokenFilter f) {
        var bean = new FilterRegistrationBean<>(f); bean.setEnabled(false); return bean;
    }
    @Bean SecurityFilterChain chain(HttpSecurity http, TokenFilter f) throws Exception {
        return http.csrf(c -> c.disable())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(a -> a.requestMatchers("/", "/index.html", "/app.js", "/style.css", "/api/auth/login").permitAll()
                .requestMatchers("/api/admin/**").hasRole("ADMINISTRADOR").anyRequest().authenticated())
            .exceptionHandling(e -> e.authenticationEntryPoint((q,r,x) -> fail(r,401,"Debes iniciar sesión"))
                .accessDeniedHandler((q,r,x) -> fail(r,403,"No tienes permisos para esta operación")))
            .addFilterBefore(f, UsernamePasswordAuthenticationFilter.class).build();
    }
    static void fail(HttpServletResponse r, int status, String message) throws IOException {
        r.setStatus(status); r.setContentType("application/json;charset=UTF-8");
        r.getWriter().write("{\"message\":\""+message+"\"}");
    }
    static class TokenFilter extends OncePerRequestFilter {
        final Users users;
        TokenFilter(Users users) { this.users=users; }
        @Override protected void doFilterInternal(HttpServletRequest q, HttpServletResponse r, FilterChain chain) throws ServletException, IOException {
            String auth=q.getHeader("Authorization");
            if (auth!=null && auth.startsWith("Bearer ")) {
                var ids=users.db().query("SELECT user_id FROM usuarios.auth_session WHERE token_hash=? AND expires_at>CURRENT_TIMESTAMP",
                    (rs,n)->rs.getObject(1,UUID.class),hash(auth.substring(7)));
                if (!ids.isEmpty()) {
                    var u=users.byId(ids.get(0));
                    if (u.active()) {
                        var permissions=u.roles().stream().map(role->new SimpleGrantedAuthority("ROLE_"+role.name())).toList();
                        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(u,null,permissions));
                        if (u.mustChangePassword() && q.getRequestURI().startsWith("/api/") &&
                            !Set.of("/api/auth/me","/api/auth/password","/api/auth/logout").contains(q.getRequestURI())) {
                            fail(r,403,"Debes cambiar tu contraseña temporal"); return;
                        }
                    }
                }
            }
            chain.doFilter(q,r);
        }
    }
}
