package com.titulacionammo.glassflow.logistica.util;

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
}
