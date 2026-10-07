package glass_inventory_api.logistica.dto;

import glass_inventory_api.logistica.model.Despacho;
import glass_inventory_api.logistica.model.EstadoDespacho;
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
public class DespachoResponse {

    private UUID id;
    private PedidoResponse pedido;
    private ChoferResponse chofer;
    private LocalDateTime fechaAsignacion;
    private LocalDateTime fechaEntrega;
    private String firmaUrl;
    private String fotoPodUrl;
    private Double latitudEntrega;
    private Double longitudEntrega;
    private Double desviacionMetros;
    private Boolean alertaDesviacion;
    private EstadoDespacho estado;
    private String comentarios;

    public static DespachoResponse fromEntity(Despacho d) {
        if (d == null) return null;
        return DespachoResponse.builder()
                .id(d.getId())
                .pedido(PedidoResponse.fromEntity(d.getPedido()))
                .chofer(ChoferResponse.fromEntity(d.getChofer()))
                .fechaAsignacion(d.getFechaAsignacion())
                .fechaEntrega(d.getFechaEntrega())
                .firmaUrl(d.getFirmaUrl())
                .fotoPodUrl(d.getFotoPodUrl())
                .latitudEntrega(GeometryUtil.getLatitude(d.getCoordenadaEntrega()))
                .longitudEntrega(GeometryUtil.getLongitude(d.getCoordenadaEntrega()))
                .desviacionMetros(d.getDesviacionMetros())
                .alertaDesviacion(d.getAlertaDesviacion())
                .estado(d.getEstado())
                .comentarios(d.getComentarios())
                .build();
    }
}
