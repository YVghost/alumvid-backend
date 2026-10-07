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
public class CerrarEntregaRequest {

    @NotBlank(message = "La fotografía de evidencia (PoD) es obligatoria para certificar la entrega.")
    private String fotoPodUrl;

    @NotBlank(message = "La firma táctil del cliente es obligatoria.")
    private String firmaUrl;

    @NotNull(message = "La latitud GPS capturada al firmar es obligatoria para auditoría.")
    private Double latitud;

    @NotNull(message = "La longitud GPS capturada al firmar es obligatoria para auditoría.")
    private Double longitud;

    private String comentarios;
}
