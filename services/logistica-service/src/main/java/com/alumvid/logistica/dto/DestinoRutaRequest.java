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
public class DestinoRutaRequest {
    @NotBlank(message = "El cliente o razon social es obligatorio")
    private String cliente;

    @NotBlank(message = "La direccion de entrega es obligatoria")
    private String direccionTexto;

    @NotNull(message = "La latitud de destino es obligatoria")
    private Double latitudDestino;

    @NotNull(message = "La longitud de destino es obligatoria")
    private Double longitudDestino;

    private String comentarios;
}
