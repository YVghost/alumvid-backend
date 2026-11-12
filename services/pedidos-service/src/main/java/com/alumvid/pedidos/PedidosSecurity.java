package com.alumvid.pedidos;

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
import org.springframework.http.HttpMethod;

@Configuration
class PedidosSecurity {
    @Bean SecurityFilterChain pedidosChain(HttpSecurity http,AuthClient auth) throws Exception {
        var filter=new OncePerRequestFilter() {
            protected boolean shouldNotFilter(HttpServletRequest r) {return !r.getRequestURI().startsWith("/api/")||r.getRequestURI().equals("/api/pedidos/auth/login");}
            protected void doFilterInternal(HttpServletRequest q,HttpServletResponse r,FilterChain chain) throws IOException,ServletException {
                String token=q.getHeader("Authorization");
                if(token==null||!token.startsWith("Bearer ")) {fail(r,401,"Debes iniciar sesion");return;}
                try {
                    var actor=auth.identity(token);
                    if(actor.mustChangePassword()&&!Set.of("/api/pedidos/auth/me","/api/pedidos/auth/password","/api/pedidos/auth/logout").contains(q.getRequestURI())) {fail(r,403,"Debes cambiar la clave temporal");return;}
                    SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(actor,null,actor.roles().stream().map(role->new SimpleGrantedAuthority("ROLE_"+role)).toList()));
                } catch(PedidosError e) {fail(r,e.status,e.getMessage());return;}
                chain.doFilter(q,r);
            }
        };
        return http.csrf(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(a->a.requestMatchers("/","/index.html","/app.js","/style.css","/api/pedidos/auth/login","/actuator/health").permitAll()
                .requestMatchers("/api/pedidos/auth/**").authenticated()
                .requestMatchers(HttpMethod.GET,"/api/**").hasAnyRole("ADMINISTRADOR","VENDEDOR","BODEGUERO")
                .requestMatchers("/api/pedidos/availability").hasAnyRole("ADMINISTRADOR","VENDEDOR","BODEGUERO")
                .requestMatchers("/api/pedidos/clients","/api/pedidos/clients/*").hasAnyRole("ADMINISTRADOR","VENDEDOR")
                .requestMatchers("/api/pedidos/orders","/api/pedidos/orders/*/confirm","/api/pedidos/orders/*/retry","/api/pedidos/orders/*/cancel").hasAnyRole("ADMINISTRADOR","VENDEDOR")
                .requestMatchers("/api/pedidos/orders/*/shipments","/api/pedidos/shipments/*/receive-return").hasAnyRole("ADMINISTRADOR","BODEGUERO")
                .requestMatchers("/api/pedidos/orders/*/prepare","/api/pedidos/orders/*/dispatch","/api/pedidos/orders/*/deliver","/api/pedidos/orders/*/receive-return").hasAnyRole("ADMINISTRADOR","BODEGUERO")
                .requestMatchers("/api/pedidos/orders/*/delay","/api/pedidos/orders/*/resume").hasAnyRole("ADMINISTRADOR","VENDEDOR","BODEGUERO")
                .anyRequest().denyAll())
            .exceptionHandling(e->e.authenticationEntryPoint((q,r,x)->fail(r,401,"Debes iniciar sesion")).accessDeniedHandler((q,r,x)->fail(r,403,"Sin permisos")))
            .addFilterBefore(filter,UsernamePasswordAuthenticationFilter.class).build();
    }
    static void fail(HttpServletResponse r,int status,String message) throws IOException {r.setStatus(status);r.setContentType("application/json;charset=UTF-8");r.getWriter().write("{\"message\":\""+message+"\"}");}
}
