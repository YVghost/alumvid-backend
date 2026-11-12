package com.alumvid.gateway.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * Endpoint de estado y metadatos del API Gateway unificado de AlumVid.
 */
@RestController
public class GatewayInfoController {
    @Value("${GOOGLE_MAPS_API_KEY:}")
    private String mapsKey;

    // Clave de cliente visible al navegador; restringirla por HTTP referrer en Google Cloud.
    @GetMapping(value="/maps-loader.js", produces="application/javascript")
    public String mapsLoader() {
        if (mapsKey == null || mapsKey.isBlank()) return "console.warn('Google Maps no configurado');";
        String key = URLEncoder.encode(mapsKey, StandardCharsets.UTF_8);
        return "document.write('<script src=\"https://maps.googleapis.com/maps/api/js?key=" + key + "&libraries=geometry\"><\\/script>');";
    }


    @GetMapping("/platform-info")
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
