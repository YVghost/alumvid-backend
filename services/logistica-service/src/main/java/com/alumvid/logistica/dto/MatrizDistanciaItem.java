package com.alumvid.logistica.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Representa el resultado de costo de viaje (duracion y distancia)
 * entre dos puntos de la red vial para optimizacion VRP / Greedy.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MatrizDistanciaItem {
    private int originIndex;
    private int destinationIndex;
    private double duracionSegundos;
    private double distanciaMetros;
    private String proveedor;
}
