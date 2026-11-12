package com.alumvid.logistica.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class AgregarPedidosRequest {
    @NotEmpty(message = "Selecciona al menos un pedido")
    @Size(max = 30)
    @Valid
    private List<PedidoRutaRequest> pedidos;
}
