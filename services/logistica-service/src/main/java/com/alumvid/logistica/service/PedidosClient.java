package com.alumvid.logistica.service;

import com.alumvid.logistica.security.Sesion;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

/**
 * Pedidos es dueño de la custodia del material. Logística le pide registrar o
 * anular el despacho de un pedido a través de su API (nunca escribe sus tablas).
 */
@Component
public class PedidosClient {
    private static final ParameterizedTypeReference<Map<String, Object>> MAPA = new ParameterizedTypeReference<>() {};
    private final RestClient client;
    private final ObjectMapper json;

    public PedidosClient(@Value("${PEDIDOS_URL:http://localhost:8085}") String url, ObjectMapper json) {
        var factory = new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
        factory.setReadTimeout(Duration.ofSeconds(15));
        this.client = RestClient.builder().baseUrl(url).requestFactory(factory).build();
        this.json = json;
    }

    /** Registra el despacho (custodia) de un pedido completo o de las líneas indicadas. */
    public Map<String, Object> despachar(UUID pedidoId, UUID choferId, UUID rutaId, UUID despachoId, UUID destinoId,
                                         List<Map<String, Object>> lineas, String motivo) {
        var body = new HashMap<String, Object>();
        body.put("requestId", UUID.nameUUIDFromBytes(("logistica:" + despachoId).getBytes()).toString());
        body.put("driverId", choferId);
        body.put("routeId", rutaId);
        body.put("dispatchId", despachoId);
        body.put("logisticsOrderId", destinoId);
        body.put("lines", lineas == null || lineas.isEmpty() ? null : lineas);
        body.put("reason", motivo);
        return post("/api/pedidos/orders/" + pedidoId + "/shipments", body);
    }

    /** Anula un despacho que aún no salió: el material vuelve a quedar preparado. */
    public void anular(UUID envioId, String motivo) {
        post("/api/pedidos/shipments/" + envioId + "/release",
                Map.of("requestId", UUID.randomUUID().toString(), "reason", motivo));
    }

    public void reasignarChofer(UUID rutaId, UUID choferId) {
        try {
            client.put().uri("/api/pedidos/shipments/driver").header("Authorization", Sesion.token())
                    .contentType(MediaType.APPLICATION_JSON).body(Map.of("routeId", rutaId, "driverId", choferId))
                    .retrieve().toBodilessEntity();
        } catch (RestClientResponseException e) {
            throw error(e);
        } catch (RestClientException e) {
            throw noDisponible();
        }
    }

    public Map<String, Object> pedido(UUID pedidoId) {
        try {
            return client.get().uri("/api/pedidos/orders/" + pedidoId).header("Authorization", Sesion.token())
                    .retrieve().body(MAPA);
        } catch (RestClientResponseException e) {
            throw error(e);
        } catch (RestClientException e) {
            throw noDisponible();
        }
    }

    private Map<String, Object> post(String uri, Object body) {
        try {
            return client.post().uri(uri).header("Authorization", Sesion.token())
                    .contentType(MediaType.APPLICATION_JSON).body(body).retrieve().body(MAPA);
        } catch (RestClientResponseException e) {
            throw error(e);
        } catch (RestClientException e) {
            throw noDisponible();
        }
    }

    /** Propaga el mensaje de negocio de pedidos (p. ej. "aún no tiene material preparado"). */
    private ResponseStatusException error(RestClientResponseException e) {
        String mensaje = "Pedidos rechazó la operación";
        try {
            var cuerpo = json.readValue(e.getResponseBodyAsString(), Map.class);
            if (cuerpo.get("message") != null) mensaje = cuerpo.get("message").toString();
        } catch (Exception ignored) {
            // Respuesta sin JSON: se usa el mensaje genérico.
        }
        var status = HttpStatus.resolve(e.getStatusCode().value());
        return new ResponseStatusException(status != null && status.is4xxClientError() ? status : HttpStatus.BAD_GATEWAY, mensaje);
    }

    private ResponseStatusException noDisponible() {
        return new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "El servicio de pedidos no está disponible");
    }
}
