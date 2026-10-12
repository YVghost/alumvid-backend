package com.alumvid.logistica.websocket;

import com.alumvid.logistica.dto.TelemetriaGpsPayload;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

/**
 * Controlador WebSocket STOMP para recepcion y retransmision en tiempo real
 * de coordenadas GPS desde la app movil del chofer hacia el panel administrativo.
 */
@Controller
@RequiredArgsConstructor
@Slf4j
public class TelemetriaWebSocketController {

    private final SimpMessagingTemplate messagingTemplate;

    @MessageMapping("/telemetria/enviar")
    public void recibirYRetransmitirTelemetria(@Payload TelemetriaGpsPayload payload) {
        if (payload == null || payload.getDespachoId() == null) {
            return;
        }

        // Si no viene timestamp, asignar el timestamp del servidor
        if (payload.getTimestamp() == null) {
            payload.setTimestamp(System.currentTimeMillis());
        }

        // 1. Difusion especifica para el despacho particular que el admin esta monitoreando
        String canalDespacho = "/topic/despachos/" + payload.getDespachoId() + "/ubicacion";
        messagingTemplate.convertAndSend(canalDespacho, payload);

        // 2. Difusion general para el mapa de flota global
        messagingTemplate.convertAndSend("/topic/choferes-activos", payload);
    }
}
