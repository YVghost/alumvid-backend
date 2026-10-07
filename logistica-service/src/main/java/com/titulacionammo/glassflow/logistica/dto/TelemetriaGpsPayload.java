package com.titulacionammo.glassflow.logistica.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

/**
 * Carga util para streaming de telemetria GPS transmitido desde la app movil del chofer.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TelemetriaGpsPayload {

    private UUID despachoId;
    private UUID choferId;
    private Double latitud;
    private Double longitud;
    private Double velocidadKmh;
    private Long timestamp;
}
