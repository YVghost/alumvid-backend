package com.titulacionammo.glassflow.logistica.dto;

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
public class EvidenciaPodResponse {

    private UUID despachoId;
    private String cliente;
    private String direccionCliente;
    private Double latitudCliente;
    private Double longitudCliente;
    private String choferNombre;
    private String choferEmail;
    private String fotoPodUrl;
    private String firmaUrl;
    private Double latitudEntrega;
    private Double longitudEntrega;
    private Double desviacionMetros;
    private Boolean alertaDesviacion;
    private LocalDateTime fechaEntrega;
    private String comentarios;
}
