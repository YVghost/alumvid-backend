package glass_inventory_api.logistica.dto;

import glass_inventory_api.logistica.model.Despacho;
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
public class EvidenciaPodResponse {
    private UUID despachoId;
    private UUID pedidoId;
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

    public static EvidenciaPodResponse fromEntity(Despacho d) {
        if (d == null) return null;
        return EvidenciaPodResponse.builder()
                .despachoId(d.getId())
                .pedidoId(d.getPedido().getId())
                .cliente(d.getPedido().getCliente())
                .direccionCliente(d.getPedido().getDireccionTexto())
                .latitudCliente(GeometryUtil.getLatitude(d.getPedido().getCoordenadaDestino()))
                .longitudCliente(GeometryUtil.getLongitude(d.getPedido().getCoordenadaDestino()))
                .choferNombre(d.getChofer().getNombre())
                .choferEmail(d.getChofer().getEmail())
                .fotoPodUrl(d.getFotoPodUrl())
                .firmaUrl(d.getFirmaUrl())
                .latitudEntrega(GeometryUtil.getLatitude(d.getCoordenadaEntrega()))
                .longitudEntrega(GeometryUtil.getLongitude(d.getCoordenadaEntrega()))
                .desviacionMetros(d.getDesviacionMetros())
                .alertaDesviacion(d.getAlertaDesviacion())
                .fechaEntrega(d.getFechaEntrega())
                .comentarios(d.getComentarios())
                .build();
    }
}
