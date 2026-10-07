package glass_inventory_api.logistica.dto;

import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AsignarDespachoRequest {

    @NotNull(message = "El ID del pedido es obligatorio.")
    private UUID pedidoId;

    @NotNull(message = "El ID del chofer es obligatorio.")
    private UUID choferId;
}
