package com.alumvid.logistica.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CrearPedidoRequest {

    @NotBlank(message = "El nombre del cliente es obligatorio.")
    private String cliente;

    @NotBlank(message = "La direccion de entrega es obligatoria.")
    private String direccionTexto;

    @NotNull(message = "La latitud destino es obligatoria.")
    private Double latitud;

    @NotNull(message = "La longitud destino es obligatoria.")
    private Double longitud;
}
