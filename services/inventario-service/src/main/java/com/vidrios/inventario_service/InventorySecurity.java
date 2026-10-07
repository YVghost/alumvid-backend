package com.vidrios.inventario_service;

import java.io.IOException;
import java.util.Set;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.context.annotation.*;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.filter.OncePerRequestFilter;

@Configuration
class InventorySecurity {
    @Bean SecurityFilterChain inventoryFilterChain(HttpSecurity http,AuthClient auth) throws Exception {
        var filter=new OncePerRequestFilter() {
            @Override protected boolean shouldNotFilter(HttpServletRequest r) {
                return !r.getRequestURI().startsWith("/api/") || r.getRequestURI().equals("/api/auth/login");
            }
            @Override protected void doFilterInternal(HttpServletRequest q,HttpServletResponse r,FilterChain chain) throws ServletException,IOException {
                String token=q.getHeader("Authorization");
                if(token==null || !token.startsWith("Bearer ")) { fail(r,401,"Debes iniciar sesión"); return; }
                try {
                    var identity=auth.identity(token);
                    if(identity.mustChangePassword() && !Set.of("/api/auth/me","/api/auth/password","/api/auth/logout").contains(q.getRequestURI())) {
                        fail(r,403,"Debes cambiar tu contraseña temporal");return;
                    }
                    var roles=identity.roles().stream().map(role->new SimpleGrantedAuthority("ROLE_"+role)).toList();
                    SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(identity,null,roles));
                } catch(InventoryError e) { fail(r,e.status,e.getMessage()); return; }
                chain.doFilter(q,r);
            }
        };
        return http.csrf(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(a->a.requestMatchers("/","/index.html","/app.js","/style.css","/api/auth/login","/actuator/health").permitAll()
                .requestMatchers("/api/auth/**").authenticated()
                .requestMatchers(org.springframework.http.HttpMethod.GET,"/api/**").hasAnyRole("ADMINISTRADOR","VENDEDOR","BODEGUERO")
                .requestMatchers(org.springframework.http.HttpMethod.POST,"/api/products/*/movements").hasAnyRole("ADMINISTRADOR","BODEGUERO")
                .requestMatchers("/api/**").hasRole("ADMINISTRADOR").anyRequest().denyAll())
            .exceptionHandling(e->e.authenticationEntryPoint((q,r,x)->fail(r,401,"Debes iniciar sesión"))
                .accessDeniedHandler((q,r,x)->fail(r,403,"No tienes permisos para esta operación")))
            .addFilterBefore(filter,UsernamePasswordAuthenticationFilter.class).build();
    }
    static void fail(HttpServletResponse response,int status,String message) throws IOException {
        response.setStatus(status);response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write("{\"message\":\""+message+"\"}");
    }
}
