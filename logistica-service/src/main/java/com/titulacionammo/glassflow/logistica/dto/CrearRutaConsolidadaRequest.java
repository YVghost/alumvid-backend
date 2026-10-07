package com.titulacionammo.glassflow.logistica.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CrearRutaConsolidadaRequest {

    @NotNull(message = "El ID del chofer es obligatorio")
    private UUID choferId;

    @NotEmpty(message = "Debe asignar al menos un pedido a la ruta consolidada")
    private List<UUID> pedidoIds;

    private String comentarios;
}
