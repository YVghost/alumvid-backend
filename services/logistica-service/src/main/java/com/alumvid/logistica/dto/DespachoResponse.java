package com.alumvid.logistica.dto;

import com.alumvid.logistica.model.EstadoDespacho;
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
public class DespachoResponse {

    private UUID id;
    private UUID rutaId;
    private Integer ordenParada;
    private PedidoResponse pedido;
    private ChoferResponse chofer;
    private LocalDateTime fechaAsignacion;
    private LocalDateTime fechaInicioRuta;
    private LocalDateTime fechaEntrega;
    private String fotoPodUrl;
    private String firmaUrl;
    private Double latitudEntrega;
    private Double longitudEntrega;
    private Double desviacionMetros;
    private Boolean alertaDesviacion;
    private EstadoDespacho estado;
    private String comentarios;
}
