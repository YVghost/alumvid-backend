package com.titulacionammo.glassflow.logistica.dto;

import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AsignarDespachoRequest {

    @NotNull(message = "El identificador del pedido es obligatorio.")
    private UUID pedidoId;

    @NotNull(message = "El identificador del chofer es obligatorio.")
    private UUID choferId;
}
