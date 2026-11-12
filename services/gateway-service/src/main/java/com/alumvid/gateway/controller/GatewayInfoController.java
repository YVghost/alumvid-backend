package com.alumvid.gateway.controller;

import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Estado del API Gateway. Las apps lo usan para detectar el servidor en la red
 * (la app móvil busca "AlumVid API Gateway" en /platform-info).
 */
@RestController
public class GatewayInfoController {

    @GetMapping("/platform-info")
    public ResponseEntity<Map<String, Object>> root() {
        return ResponseEntity.ok(Map.of(
            "status", "UP",
            "service", "AlumVid API Gateway",
            "version", "3.0.0",
            "routes", Map.of(
                "usuarios", "/api/v1/auth/**, /api/v1/admin/**",
                "inventario", "/api/products/**",
                "retazos", "/api/retazos/**",
                "ubicaciones", "/api/ubicaciones/**",
                "pedidos", "/api/pedidos/**",
                "logistica", "/api/v1/logistica/**, /ws-logistica/**"
            )
        ));
    }
}
