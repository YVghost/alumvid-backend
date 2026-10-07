package glass_inventory_api.logistica.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CrearPedidoRequest {

    @NotBlank(message = "El nombre del cliente es obligatorio.")
    private String cliente;

    @NotBlank(message = "La dirección de entrega es obligatoria.")
    private String direccionTexto;

    @NotNull(message = "La latitud de destino es obligatoria.")
    private Double latitud;

    @NotNull(message = "La longitud de destino es obligatoria.")
    private Double longitud;
}
