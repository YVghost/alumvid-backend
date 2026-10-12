package com.alumvid.logistica.model;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;
import org.locationtech.jts.geom.Point;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Entidad de persistencia para despachos y control de telemetria en tiempo real.
 */
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

    @ManyToOne(optional = false, fetch = FetchType.EAGER)
    @JoinColumn(name = "pedido_id", nullable = false)
    private Pedido pedido;

    @ManyToOne(optional = true, fetch = FetchType.EAGER)
    @JoinColumn(name = "chofer_id", nullable = true)
    private Chofer chofer;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ruta_id")
    @com.fasterxml.jackson.annotation.JsonIgnore
    @ToString.Exclude
    private Ruta ruta;

    @Column(name = "orden_parada")
    private Integer ordenParada;

    @Column(name = "fecha_asignacion", nullable = false)
    private LocalDateTime fechaAsignacion;

    @Column(name = "fecha_inicio_ruta")
    private LocalDateTime fechaInicioRuta;

    @Column(name = "fecha_entrega")
    private LocalDateTime fechaEntrega;

    @Column(name = "foto_pod_url", columnDefinition = "TEXT")
    private String fotoPodUrl;

    @Column(name = "firma_url", columnDefinition = "TEXT")
    private String firmaUrl;

    @Column(name = "coordenada_entrega", columnDefinition = "geometry(Point, 4326)")
    private Point coordenadaEntrega;

    @Column(name = "desviacion_metros")
    private Double desviacionMetros;

    @Column(name = "alerta_desviacion")
    private Boolean alertaDesviacion;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 30)
    @Builder.Default
    private EstadoDespacho estado = EstadoDespacho.PENDIENTE;

    @Column(columnDefinition = "TEXT")
    private String comentarios;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
}
