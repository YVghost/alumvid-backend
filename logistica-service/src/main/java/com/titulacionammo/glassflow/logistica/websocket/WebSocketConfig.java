package com.titulacionammo.glassflow.logistica.websocket;

import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

/**
 * Configuracion del broker de mensajes WebSocket con protocolo STOMP
 * para streaming bidireccional de telemetria GPS en tiempo real.
 */
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        // Prefijo para suscripciones de clientes (ej. /topic/despachos/{id}/ubicacion)
        config.enableSimpleBroker("/topic");
        // Prefijo para mensajes enviados desde clientes hacia el servidor (ej. /app/telemetria/enviar)
        config.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // Endpoint WebSocket principal con soporte SockJS para navegadores y conexion pura para apps moviles
        registry.addEndpoint("/ws-logistica")
                .setAllowedOriginPatterns("*")
                .withSockJS();

        registry.addEndpoint("/ws-logistica")
                .setAllowedOriginPatterns("*");
    }
}
