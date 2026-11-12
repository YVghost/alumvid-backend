package com.alumvid.pedidos;

import java.util.Map;

/**
 * Validación de identificaciones y teléfonos de Ecuador.
 * <ul>
 *   <li>Cédula: 10 dígitos, provincia 01-24 o 30, tercer dígito 0-5 y dígito verificador módulo 10.</li>
 *   <li>RUC persona natural: cédula válida + establecimiento (001...).</li>
 *   <li>RUC sociedad privada / extranjero: tercer dígito 9, verificador módulo 11 (coef. 4,3,2,7,6,5,4,3,2).</li>
 *   <li>RUC entidad pública: tercer dígito 6, verificador módulo 11 (coef. 3,2,7,6,5,4,3,2).</li>
 *   <li>Consumidor final: 9999999999999.</li>
 * </ul>
 * Copia idéntica en usuarios-service y pedidos-service (cada servicio se despliega por separado).
 */
public final class IdentificacionEcuador {
    private IdentificacionEcuador() {}

    public enum Tipo { CEDULA, RUC_PERSONA_NATURAL, RUC_SOCIEDAD_PRIVADA, RUC_ENTIDAD_PUBLICA, CONSUMIDOR_FINAL }

    public record Resultado(boolean valida, Tipo tipo, String provincia, String mensaje) {
        static Resultado error(String mensaje) { return new Resultado(false, null, null, mensaje); }
    }

    public static final String CONSUMIDOR_FINAL = "9999999999999";

    private static final Map<Integer, String> PROVINCIAS = Map.ofEntries(
        Map.entry(1, "Azuay"), Map.entry(2, "Bolívar"), Map.entry(3, "Cañar"), Map.entry(4, "Carchi"),
        Map.entry(5, "Cotopaxi"), Map.entry(6, "Chimborazo"), Map.entry(7, "El Oro"), Map.entry(8, "Esmeraldas"),
        Map.entry(9, "Guayas"), Map.entry(10, "Imbabura"), Map.entry(11, "Loja"), Map.entry(12, "Los Ríos"),
        Map.entry(13, "Manabí"), Map.entry(14, "Morona Santiago"), Map.entry(15, "Napo"), Map.entry(16, "Pastaza"),
        Map.entry(17, "Pichincha"), Map.entry(18, "Tungurahua"), Map.entry(19, "Zamora Chinchipe"),
        Map.entry(20, "Galápagos"), Map.entry(21, "Sucumbíos"), Map.entry(22, "Orellana"),
        Map.entry(23, "Santo Domingo de los Tsáchilas"), Map.entry(24, "Santa Elena"),
        Map.entry(30, "Ecuatorianos registrados en el exterior"));

    /** Analiza una cédula o RUC y devuelve si es válida, su tipo y la provincia de emisión. */
    public static Resultado analizar(String valor) {
        String v = valor == null ? "" : valor.trim();
        if (v.isEmpty()) return Resultado.error("Ingresa la cédula o RUC");
        if (!v.chars().allMatch(Character::isDigit)) return Resultado.error("La cédula o RUC solo admite números");
        if (v.equals(CONSUMIDOR_FINAL)) return new Resultado(true, Tipo.CONSUMIDOR_FINAL, null, "Consumidor final");
        if (v.length() != 10 && v.length() != 13) return Resultado.error("La cédula tiene 10 dígitos y el RUC 13");
        int provincia = Integer.parseInt(v.substring(0, 2));
        String nombreProvincia = PROVINCIAS.get(provincia);
        if (nombreProvincia == null) return Resultado.error("Código de provincia inválido (" + v.substring(0, 2) + ")");
        int tercero = v.charAt(2) - '0';
        if (v.length() == 10) {
            if (tercero > 5) return Resultado.error("Una cédula tiene tercer dígito entre 0 y 5");
            return cedulaValida(v)
                ? new Resultado(true, Tipo.CEDULA, nombreProvincia, "Cédula de " + nombreProvincia)
                : Resultado.error("Cédula inválida: el dígito verificador no coincide");
        }
        if (tercero <= 5) {
            if (!cedulaValida(v.substring(0, 10))) return Resultado.error("RUC inválido: la cédula base no es válida");
            if (Integer.parseInt(v.substring(10)) < 1) return Resultado.error("RUC inválido: establecimiento 000");
            return new Resultado(true, Tipo.RUC_PERSONA_NATURAL, nombreProvincia, "RUC de persona natural de " + nombreProvincia);
        }
        if (tercero == 6) {
            if (modulo11(v, new int[]{3, 2, 7, 6, 5, 4, 3, 2}) != v.charAt(8) - '0') return Resultado.error("RUC público inválido: el dígito verificador no coincide");
            if (Integer.parseInt(v.substring(9)) < 1) return Resultado.error("RUC inválido: establecimiento 0000");
            return new Resultado(true, Tipo.RUC_ENTIDAD_PUBLICA, nombreProvincia, "RUC de entidad pública de " + nombreProvincia);
        }
        if (tercero == 9) {
            if (modulo11(v, new int[]{4, 3, 2, 7, 6, 5, 4, 3, 2}) != v.charAt(9) - '0') return Resultado.error("RUC de sociedad inválido: el dígito verificador no coincide");
            if (Integer.parseInt(v.substring(10)) < 1) return Resultado.error("RUC inválido: establecimiento 000");
            return new Resultado(true, Tipo.RUC_SOCIEDAD_PRIVADA, nombreProvincia, "RUC de sociedad privada de " + nombreProvincia);
        }
        return Resultado.error("Tercer dígito inválido para un RUC (" + tercero + ")");
    }

    private static boolean cedulaValida(String c) {
        int suma = 0;
        for (int i = 0; i < 9; i++) {
            int d = (c.charAt(i) - '0') * (i % 2 == 0 ? 2 : 1);
            suma += d > 9 ? d - 9 : d;
        }
        return (10 - suma % 10) % 10 == c.charAt(9) - '0';
    }

    private static int modulo11(String v, int[] coeficientes) {
        int suma = 0;
        for (int i = 0; i < coeficientes.length; i++) suma += (v.charAt(i) - '0') * coeficientes[i];
        int r = suma % 11;
        return r == 0 ? 0 : 11 - r;
    }

    /**
     * Normaliza un teléfono de Ecuador: celular 09XXXXXXXX o fijo 0[2-7]XXXXXXX.
     * Acepta +593 / 593, espacios, guiones y paréntesis. Devuelve "" si viene vacío.
     * @throws IllegalArgumentException con un mensaje para el usuario si no es válido.
     */
    public static String telefono(String valor) {
        String v = valor == null ? "" : valor.trim();
        if (v.isEmpty()) return "";
        if (!v.matches("[+0-9 ()\\-]+")) throw new IllegalArgumentException("El teléfono solo admite números");
        String d = v.replaceAll("[^0-9]", "");
        if (d.startsWith("593")) d = "0" + d.substring(3);
        if (d.matches("09\\d{8}") || d.matches("0[2-7]\\d{7}")) return d;
        throw new IllegalArgumentException("Teléfono inválido: usa un celular 09XXXXXXXX o un fijo con código de provincia (02XXXXXXX)");
    }
}
