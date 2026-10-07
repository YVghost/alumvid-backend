package com.vidrios.inventario_service;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.*;

@Component
class AuthClient {
    record Identity(UUID id,String identification,String fullName,Set<String> roles,boolean master,boolean active,boolean mustChangePassword) {
        boolean has(String role) { return roles.contains(role); }
    }
    private final RestClient client;
    AuthClient(@Value("${app.auth-url}") String url) {
        var factory=new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build());
        factory.setReadTimeout(Duration.ofSeconds(3));
        client=RestClient.builder().baseUrl(url).requestFactory(factory).build();
    }
    Identity identity(String authorization) {
        try {
            var identity=client.get().uri("/api/auth/me").header("Authorization",authorization).retrieve().body(Identity.class);
            if(identity==null || !identity.active()) throw new InventoryError(401,"Sesión inválida");
            return identity;
        } catch(RestClientResponseException e) {
            if(e.getStatusCode().value()==401 || e.getStatusCode().value()==403) throw new InventoryError(401,"Sesión inválida o vencida");
            throw new InventoryError(503,"El servicio de usuarios no está disponible");
        } catch(RestClientException e) { throw new InventoryError(503,"El servicio de usuarios no está disponible"); }
    }
    org.springframework.http.ResponseEntity<String> forward(String path,String authorization,Object body) {
        try {
            var request=client.post().uri("/api/auth/"+path).header("Content-Type","application/json");
            if(authorization!=null) request.header("Authorization",authorization);
            if(body!=null) request.body(body);
            var response=request.retrieve().toEntity(String.class);
            return org.springframework.http.ResponseEntity.status(response.getStatusCode()).contentType(org.springframework.http.MediaType.APPLICATION_JSON).body(response.getBody());
        } catch(RestClientResponseException e) {
            if(e.getStatusCode().is4xxClientError()) return org.springframework.http.ResponseEntity.status(e.getStatusCode()).contentType(org.springframework.http.MediaType.APPLICATION_JSON).body(e.getResponseBodyAsString());
            throw new InventoryError(503,"El servicio de usuarios no está disponible");
        } catch(RestClientException e) { throw new InventoryError(503,"El servicio de usuarios no está disponible"); }
    }
}
