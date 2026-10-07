package glass_inventory_api.logistica.dto;

import glass_inventory_api.logistica.model.Chofer;
import glass_inventory_api.logistica.model.EstadoChofer;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChoferResponse {
    private UUID id;
    private String nombre;
    private String email;
    private String telefono;
    private EstadoChofer estadoDisponibilidad;

    public static ChoferResponse fromEntity(Chofer c) {
        if (c == null) return null;
        return ChoferResponse.builder()
                .id(c.getId())
                .nombre(c.getNombre())
                .email(c.getEmail())
                .telefono(c.getTelefono())
                .estadoDisponibilidad(c.getEstadoDisponibilidad())
                .build();
    }
}
