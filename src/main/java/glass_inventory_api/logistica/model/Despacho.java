package glass_inventory_api.logistica.model;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;
import org.locationtech.jts.geom.Point;

import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "despachos")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Despacho {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @OneToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "pedido_id", nullable = false, unique = true)
    private Pedido pedido;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "chofer_id", nullable = false)
    private Chofer chofer;

    @Column(name = "fecha_asignacion", nullable = false)
    private LocalDateTime fechaAsignacion;

    @Column(name = "fecha_entrega")
    private LocalDateTime fechaEntrega;

    @Column(name = "firma_url", length = 1000)
    private String firmaUrl;

    @Column(name = "foto_pod_url", length = 1000)
    private String fotoPodUrl;

    @Column(name = "coordenada_entrega", columnDefinition = "geometry(Point, 4326)")
    private Point coordenadaEntrega;

    @Column(name = "desviacion_metros")
    private Double desviacionMetros;

    @Column(name = "alerta_desviacion")
    @Builder.Default
    private Boolean alertaDesviacion = false;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    @Builder.Default
    private EstadoDespacho estado = EstadoDespacho.PENDIENTE;

    @Column(name = "comentarios", length = 500)
    private String comentarios;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
}
