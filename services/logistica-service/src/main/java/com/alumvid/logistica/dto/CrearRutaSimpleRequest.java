package com.alumvid.logistica.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CrearRutaSimpleRequest {
    /** Opcional: si no se indica se genera RUTA-aaaammdd-hhmm. */
    private String codigoRuta;
    @jakarta.validation.constraints.NotNull(message = "Selecciona un chofer disponible")
    private UUID choferId;
    private String comentarios;
    /** Pedidos que se agregan al crear la ruta (opcional). */
    @jakarta.validation.Valid
    private java.util.List<PedidoRutaRequest> pedidos;
}
