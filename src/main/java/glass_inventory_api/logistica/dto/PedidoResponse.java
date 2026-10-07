package glass_inventory_api.logistica.dto;

import glass_inventory_api.logistica.model.EstadoPedido;
import glass_inventory_api.logistica.model.Pedido;
import glass_inventory_api.logistica.util.GeometryUtil;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.UUID;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PedidoResponse {
    private UUID id;
    private String cliente;
    private String direccionTexto;
    private Double latitudDestino;
    private Double longitudDestino;
    private EstadoPedido estado;
    private LocalDateTime fechaSolicitud;

    public static PedidoResponse fromEntity(Pedido p) {
        if (p == null) return null;
        return PedidoResponse.builder()
                .id(p.getId())
                .cliente(p.getCliente())
                .direccionTexto(p.getDireccionTexto())
                .latitudDestino(GeometryUtil.getLatitude(p.getCoordenadaDestino()))
                .longitudDestino(GeometryUtil.getLongitude(p.getCoordenadaDestino()))
                .estado(p.getEstado())
                .fechaSolicitud(p.getFechaSolicitud())
                .build();
    }
}
