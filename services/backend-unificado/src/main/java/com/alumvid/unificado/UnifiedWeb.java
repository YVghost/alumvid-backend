package com.alumvid.unificado;

import java.math.BigDecimal;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import com.alumvid.usuarios.Security;

@Configuration
public class UnifiedWeb {
    @Bean FilterRegistrationBean<Security.AuthFilter> disableGlobalAuthFilter(Security.AuthFilter filter) {
        var registration=new FilterRegistrationBean<>(filter);registration.setEnabled(false);return registration;
    }
    @Bean @Order(0) SecurityFilterChain publicEndpoints(HttpSecurity http) throws Exception {
        return http.securityMatcher("/actuator/health","/platform-info","/api/v1/logistica/health")
            .csrf(c->c.disable()).cors(c->{}).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(a->a.anyRequest().permitAll()).build();
    }
    @Bean @Order(100) SecurityFilterChain denyUnknownEndpoints(HttpSecurity http) throws Exception {
        return http.csrf(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(a->a.anyRequest().denyAll()).build();
    }
    @Bean Jackson2ObjectMapperBuilderCustomizer plainDecimals() {
        return builder->builder.serializerByType(BigDecimal.class,new com.fasterxml.jackson.databind.JsonSerializer<BigDecimal>() {
            @Override public void serialize(BigDecimal value,com.fasterxml.jackson.core.JsonGenerator generator,
                com.fasterxml.jackson.databind.SerializerProvider provider) throws java.io.IOException {generator.writeString(value.toPlainString());}
        });
    }
}
