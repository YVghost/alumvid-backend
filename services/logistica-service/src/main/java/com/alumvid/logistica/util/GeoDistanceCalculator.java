package com.alumvid.logistica.util;

import org.locationtech.jts.geom.Point;

/**
 * Calculador de distancia geodesica mediante la formula de Haversine.
 * Provee calculo metrico de alta precision para geofencing y auditoria de rutas.
 */
public class GeoDistanceCalculator {

    private static final double RADIO_TIERRA_METROS = 6371000.0;

    private GeoDistanceCalculator() {
    }

    /**
     * Calcula la distancia en metros entre dos puntos geograficos (WGS 84).
     */
    public static double calcularDistanciaMetros(double lat1, double lon1, double lat2, double lon2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);

        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);

        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return RADIO_TIERRA_METROS * c;
    }

    /**
     * Calcula la distancia en metros entre dos objetos Point de JTS.
     */
    public static double calcularDistanciaPuntos(Point p1, Point p2) {
        if (p1 == null || p2 == null) {
            throw new IllegalArgumentException("Los puntos geometricos no pueden ser nulos para calcular distancia.");
        }
        return calcularDistanciaMetros(p1.getY(), p1.getX(), p2.getY(), p2.getX());
    }
}
