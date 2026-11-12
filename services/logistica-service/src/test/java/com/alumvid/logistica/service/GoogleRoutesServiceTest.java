package com.alumvid.logistica.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class GoogleRoutesServiceTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    @DisplayName("Debe calcular matriz de duraciones con fallback Haversine si no hay API key")
    void testMatrizConFallbackHaversine() {
        GoogleRoutesService service = new GoogleRoutesService(objectMapper);
        ReflectionTestUtils.setField(service, "googleApiKey", "");

        List<double[]> coordenadas = new ArrayList<>();
        coordenadas.add(new double[]{-0.1807, -78.4678}); // Bodega AlumVid
        coordenadas.add(new double[]{-0.1900, -78.4800}); // Destino 1
        coordenadas.add(new double[]{-0.1700, -78.4600}); // Destino 2

        double[][] matriz = service.obtenerMatrizDuracionesViales(coordenadas);

        assertNotNull(matriz);
        assertEquals(3, matriz.length);
        assertEquals(3, matriz[0].length);

        // Diagonal principal siempre debe ser 0
        assertEquals(0.0, matriz[0][0]);
        assertEquals(0.0, matriz[1][1]);
        assertEquals(0.0, matriz[2][2]);

        // Las duraciones entre puntos distintos deben ser mayores a 0
        assertTrue(matriz[0][1] > 0.0);
        assertTrue(matriz[0][2] > 0.0);
        assertTrue(matriz[1][2] > 0.0);
    }

    @Test
    @org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable(named="GOOGLE_ROUTES_LIVE_TEST", matches="true")
    @DisplayName("Consulta externa opcional de Google Routes con clave del entorno")
    void testGoogleRoutesApiConClaveActiva() {
        GoogleRoutesService service = new GoogleRoutesService(objectMapper);
        assertNotNull(System.getenv("GOOGLE_MAPS_API_KEY"), "Configura la clave para esta prueba opcional");
        ReflectionTestUtils.setField(service, "googleApiKey", System.getenv("GOOGLE_MAPS_API_KEY"));

        List<double[]> coordenadas = new ArrayList<>();
        coordenadas.add(new double[]{-0.089290, -78.439607}); // Bodega Central Arq-AlumVid
        coordenadas.add(new double[]{-0.1900, -78.4800}); // Punto A
        coordenadas.add(new double[]{-0.1750, -78.4720}); // Punto B

        double[][] matriz = service.obtenerMatrizDuracionesViales(coordenadas);

        assertNotNull(matriz);
        assertEquals(3, matriz.length);
        assertEquals(0.0, matriz[0][0]);
        assertTrue(matriz[0][1] > 0.0, "La duracion entre Bodega y Punto A debe ser mayor a 0");
        assertTrue(matriz[0][2] > 0.0, "La duracion entre Bodega y Punto B debe ser mayor a 0");
    }

    @Test
    @DisplayName("Debe manejar lista unitaria o vacia sin errores")
    void testListaVacia() {
        GoogleRoutesService service = new GoogleRoutesService(objectMapper);
        double[][] matriz = service.obtenerMatrizDuracionesViales(List.of(new double[]{-0.1807, -78.4678}));
        assertEquals(1, matriz.length);
        assertEquals(0.0, matriz[0][0]);
    }
}
