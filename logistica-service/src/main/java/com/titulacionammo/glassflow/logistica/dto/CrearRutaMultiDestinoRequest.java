package com.titulacionammo.glassflow.logistica.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;
import java.util.UUID;

/**
 * Peticion para crear y ordenar automaticamente una ruta con N cantidad de destinos.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CrearRutaMultiDestinoRequest {

    @NotNull(message = "El ID del chofer es obligatorio")
    private UUID choferId;

    @NotEmpty(message = "Debe proporcionar al menos un destino para planificar la ruta")
    @Valid
    private List<DestinoItemRequest> destinos;

    private String comentarios;

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class DestinoItemRequest {
        @NotNull(message = "El cliente o razon social es obligatorio")
        private String cliente;

        @NotNull(message = "La direccion de entrega es obligatoria")
        private String direccionTexto;

        @NotNull(message = "La latitud de destino es obligatoria")
        private Double latitudDestino;

        @NotNull(message = "La longitud de destino es obligatoria")
        private Double longitudDestino;
    }
}
