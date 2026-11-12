package com.alumvid.logistica.service;

import com.alumvid.logistica.util.GeoDistanceCalculator;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.*;

/**
 * Servicio de integracion con Google Routes API (computeRouteMatrix)
 * para obtencion de matrices de duracion y distancia sobre la red vial real.
 * Incorpora arquitectura de resiliencia con fallback a OSRM Table Service y Haversine.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class GoogleRoutesService {

    private static final String GOOGLE_ROUTES_MATRIX_URL = "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix";
    private static final String OSRM_TABLE_URL_BASE = "https://router.project-osrm.org/table/v1/driving/";
    private static final double VELOCIDAD_URBANA_PROMEDIO_MPS = 25.0 * 1000.0 / 3600.0; // ~6.94 m/s (25 km/h en Quito)

    private final ObjectMapper objectMapper;

    @Value("${alumvid.google.maps.api-key:}")
    private String googleApiKey;

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(4))
            .build();

    /**
     * Calcula la matriz completa NxN de tiempos de viaje en segundos entre todos los puntos.
     * Retorna matriz[origenIndex][destinoIndex] = segundos.
     *
     * @param coordenadas Lista de puntos en formato [latitud, longitud]
     */
    public double[][] obtenerMatrizDuracionesViales(List<double[]> coordenadas) {
        int n = coordenadas.size();
        double[][] matriz = new double[n][n];

        if (n <= 1) {
            return matriz;
        }

        // 1. Intentar con Google Routes API
        try {
            if (googleApiKey != null && !googleApiKey.isBlank()) {
                double[][] googleResult = consultarGoogleRoutesMatrix(coordenadas);
                if (googleResult != null) {
                    log.info("Matriz vial calculada exitosamente con Google Routes API ({} puntos)", n);
                    return googleResult;
                }
            }
        } catch (Exception e) {
            log.warn("Google Routes API no disponible o fallo de conexion: {}. Conmutando a OSRM.", e.getMessage());
        }

        // 2. Fallback a OSRM Table Service
        try {
            double[][] osrmResult = consultarOsrmTable(coordenadas);
            if (osrmResult != null) {
                log.info("Matriz vial calculada mediante fallback OSRM Table ({} puntos)", n);
                return osrmResult;
            }
        } catch (Exception e) {
            log.warn("OSRM Table Service no disponible: {}. Conmutando a Haversine geodesico.", e.getMessage());
        }

        // 3. Fallback final: Haversine geodesico con velocidad urbana promedio
        log.warn("Utilizando estimacion geodesica Haversine para matriz de duraciones.");
        return calcularMatrizHaversine(coordenadas);
    }

    private double[][] consultarGoogleRoutesMatrix(List<double[]> coordenadas) throws Exception {
        int n = coordenadas.size();
        List<Map<String, Object>> waypoints = new ArrayList<>();
        for (double[] coord : coordenadas) {
            waypoints.add(Map.of(
                    "waypoint", Map.of(
                            "location", Map.of(
                                    "latLng", Map.of(
                                            "latitude", coord[0],
                                            "longitude", coord[1]
                                    )
                            )
                    )
            ));
        }

        Map<String, Object> requestBody = Map.of(
                "origins", waypoints,
                "destinations", waypoints,
                "travelMode", "DRIVE"
        );

        String jsonPayload = objectMapper.writeValueAsString(requestBody);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(GOOGLE_ROUTES_MATRIX_URL))
                .timeout(Duration.ofSeconds(6))
                .header("Content-Type", "application/json")
                .header("X-Goog-Api-Key", googleApiKey.trim())
                .header("X-Goog-FieldMask", "originIndex,destinationIndex,duration,distanceMeters,status")
                .POST(HttpRequest.BodyPublishers.ofString(jsonPayload))
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            log.warn("Google Routes API respondio status {}: {}", response.statusCode(), response.body());
            return null;
        }

        JsonNode arrayNode = objectMapper.readTree(response.body());
        if (!arrayNode.isArray() || arrayNode.isEmpty()) {
            return null;
        }

        double[][] matriz = new double[n][n];
        for (JsonNode item : arrayNode) {
            int orig = item.path("originIndex").asInt(0);
            int dest = item.path("destinationIndex").asInt(0);

            String durationStr = item.path("duration").asText("0s");
            double segundos = parsearSegundos(durationStr);

            if (orig < n && dest < n) {
                matriz[orig][dest] = segundos;
            }
        }

        return matriz;
    }

    private double[][] consultarOsrmTable(List<double[]> coordenadas) throws Exception {
        int n = coordenadas.size();
        // OSRM usa formato: lon,lat;lon,lat...
        StringBuilder sb = new StringBuilder(OSRM_TABLE_URL_BASE);
        for (int i = 0; i < n; i++) {
            if (i > 0) sb.append(";");
            sb.append(coordenadas.get(i)[1]).append(",").append(coordenadas.get(i)[0]);
        }
        sb.append("?annotations=duration");

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(sb.toString()))
                .timeout(Duration.ofSeconds(6))
                .header("User-Agent", "AlumVid-Logistica-Server/2.0")
                .GET()
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) {
            return null;
        }

        JsonNode root = objectMapper.readTree(response.body());
        if (!"Ok".equalsIgnoreCase(root.path("code").asText())) {
            return null;
        }

        JsonNode durations = root.path("durations");
        if (!durations.isArray() || durations.size() != n) {
            return null;
        }

        double[][] matriz = new double[n][n];
        for (int i = 0; i < n; i++) {
            JsonNode row = durations.get(i);
            for (int j = 0; j < n; j++) {
                matriz[i][j] = row.get(j).asDouble(0.0);
            }
        }

        return matriz;
    }

    private double[][] calcularMatrizHaversine(List<double[]> coordenadas) {
        int n = coordenadas.size();
        double[][] matriz = new double[n][n];
        for (int i = 0; i < n; i++) {
            double lat1 = coordenadas.get(i)[0];
            double lon1 = coordenadas.get(i)[1];
            for (int j = 0; j < n; j++) {
                if (i == j) {
                    matriz[i][j] = 0.0;
                } else {
                    double lat2 = coordenadas.get(j)[0];
                    double lon2 = coordenadas.get(j)[1];
                    double distMetros = GeoDistanceCalculator.calcularDistanciaMetros(lat1, lon1, lat2, lon2);
                    matriz[i][j] = distMetros / VELOCIDAD_URBANA_PROMEDIO_MPS;
                }
            }
        }
        return matriz;
    }

    private double parsearSegundos(String durationStr) {
        if (durationStr == null || durationStr.isBlank()) {
            return 0.0;
        }
        try {
            String limpio = durationStr.replace("s", "").trim();
            return Double.parseDouble(limpio);
        } catch (Exception e) {
            return 0.0;
        }
    }
}
