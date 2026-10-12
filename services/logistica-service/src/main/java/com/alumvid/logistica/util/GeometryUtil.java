package com.alumvid.logistica.util;

import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.Point;
import org.locationtech.jts.geom.PrecisionModel;

/**
 * Utilidades para construccion y conversion de geometrias espaciales en sistema WGS 84 (SRID 4326).
 */
public class GeometryUtil {

    public static final int SRID_WGS84 = 4326;
    private static final GeometryFactory FACTORY = new GeometryFactory(new PrecisionModel(), SRID_WGS84);

    private GeometryUtil() {
    }

    /**
     * Crea un objeto Point espacial a partir de latitud y longitud geograficas.
     * En JTS, la coordenada X corresponde a la Longitud y la coordenada Y a la Latitud.
     */
    public static Point crearPunto(Double latitud, Double longitud) {
        if (latitud == null || longitud == null) {
            return null;
        }
        return FACTORY.createPoint(new Coordinate(longitud, latitud));
    }

    public static Double extraerLatitud(Point punto) {
        return (punto != null) ? punto.getY() : null;
    }

    public static Double extraerLongitud(Point punto) {
        return (punto != null) ? punto.getX() : null;
    }

    /**
     * Calcula la distancia geodesica en metros entre dos coordenadas geograficas utilizando la formula de Haversine.
     */
    public static double calcularDistanciaMetros(double lat1, double lon1, double lat2, double lon2) {
        final int RADIO_TIERRA_METROS = 6371000;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return RADIO_TIERRA_METROS * c;
    }
}

