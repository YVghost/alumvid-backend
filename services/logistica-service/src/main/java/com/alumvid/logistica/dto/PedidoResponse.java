package com.alumvid.logistica.dto;

import com.alumvid.logistica.model.EstadoPedido;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PedidoResponse {

    private UUID id;
    private String cliente;
    private String direccionTexto;
    private Double latitudDestino;
    private Double longitudDestino;
    private EstadoPedido estado;
    private LocalDateTime fechaSolicitud;
}
