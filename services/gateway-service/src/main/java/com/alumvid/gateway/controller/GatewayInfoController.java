package com.alumvid.gateway.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Endpoint de estado y metadatos del API Gateway unificado de AlumVid.
 */
@RestController
public class GatewayInfoController {

    @GetMapping("/")
    public ResponseEntity<Map<String, Object>> root() {
        return ResponseEntity.ok(Map.of(
            "status", "UP",
            "service", "AlumVid API Gateway",
            "version", "2.0.0",
            "type", "Pure API Gateway (Spring Cloud Gateway MVC)",
            "routes", Map.of(
                "auth", "/api/v1/auth/**",
                "admin", "/api/v1/admin/**",
                "inventario", "/api/products/**",
                "logistica", "/api/v1/logistica/**",
                "telemetria", "/ws-logistica/**"
            )
        ));
    }
}
