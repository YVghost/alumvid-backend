package glass_inventory_api.logistica.util;

import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.Point;
import org.locationtech.jts.geom.PrecisionModel;

/**
 * Utilidad espacial para manejar tipos geométricos JTS con el SRID 4326 (WGS 84).
 */
public class GeometryUtil {

    private static final int SRID = 4326;
    private static final GeometryFactory GEOMETRY_FACTORY = new GeometryFactory(new PrecisionModel(), SRID);

    private GeometryUtil() {
    }

    /**
     * Crea un Point JTS compatible con PostGIS GEOMETRY(Point, 4326).
     * @param latitud Coordenada Y (latitud en grados decimales)
     * @param longitud Coordenada X (longitud en grados decimales)
     * @return Point con SRID 4326
     */
    public static Point createPoint(double latitud, double longitud) {
        Point point = GEOMETRY_FACTORY.createPoint(new Coordinate(longitud, latitud));
        point.setSRID(SRID);
        return point;
    }

    /**
     * Extrae la latitud (coordenada Y) de un Point.
     */
    public static Double getLatitude(Point point) {
        return point != null ? point.getY() : null;
    }

    /**
     * Extrae la longitud (coordenada X) de un Point.
     */
    public static Double getLongitude(Point point) {
        return point != null ? point.getX() : null;
    }
}
