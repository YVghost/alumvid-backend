package com.alumvid.logistica.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.List;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Pedido comercial que se agrega como parada. Sin líneas se lleva el pedido completo
 * (todo lo preparado); con líneas se ajusta la carga. Las coordenadas solo se indican
 * si el pedido no registró su ubicación de entrega.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class PedidoRutaRequest {
    @NotNull(message = "El pedido es obligatorio")
    private UUID pedidoId;
    @Valid
    private List<LineaCargaRequest> lineas;
    private Double latitud;
    private Double longitud;
}
