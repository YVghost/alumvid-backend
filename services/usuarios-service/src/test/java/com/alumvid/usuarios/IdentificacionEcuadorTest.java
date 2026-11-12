package com.alumvid.usuarios;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

/** Vectores sintéticos (no corresponden a personas reales). */
class IdentificacionEcuadorTest {

    @Test
    void cedulasValidasIndicanProvincia() {
        var r = IdentificacionEcuador.analizar("1712345675");
        assertTrue(r.valida());
        assertEquals(IdentificacionEcuador.Tipo.CEDULA, r.tipo());
        assertEquals("Pichincha", r.provincia());
        assertEquals("Guayas", IdentificacionEcuador.analizar("0912345675").provincia());
        assertEquals("Azuay", IdentificacionEcuador.analizar("0100000017").provincia());
        assertEquals("Ecuatorianos registrados en el exterior", IdentificacionEcuador.analizar("3011111113").provincia());
    }

    @Test
    void rucsPorTipo() {
        assertEquals(IdentificacionEcuador.Tipo.RUC_PERSONA_NATURAL, IdentificacionEcuador.analizar("1712345675001").tipo());
        assertEquals(IdentificacionEcuador.Tipo.RUC_SOCIEDAD_PRIVADA, IdentificacionEcuador.analizar("1791234561001").tipo());
        assertEquals(IdentificacionEcuador.Tipo.RUC_SOCIEDAD_PRIVADA, IdentificacionEcuador.analizar("0991112227001").tipo());
        assertEquals(IdentificacionEcuador.Tipo.RUC_ENTIDAD_PUBLICA, IdentificacionEcuador.analizar("1760000150001").tipo());
        assertEquals(IdentificacionEcuador.Tipo.CONSUMIDOR_FINAL, IdentificacionEcuador.analizar("9999999999999").tipo());
    }

    @Test
    void rechazaTextoYNumerosMalFormados() {
        for (String malo : new String[]{"hola", "r", "DEMO-1", "17123456A5", "0000000000", "1712345670", "2512345675",
                "1762345675", "171234567", "1712345675000", "1791234560001", "1760000190001"}) {
            assertFalse(IdentificacionEcuador.analizar(malo).valida(), malo);
        }
        assertEquals("La cédula o RUC solo admite números", IdentificacionEcuador.analizar("hola").mensaje());
    }

    @Test
    void telefonosSeNormalizan() {
        assertEquals("0991234567", IdentificacionEcuador.telefono("0991234567"));
        assertEquals("0991234567", IdentificacionEcuador.telefono("+593 99 123 4567"));
        assertEquals("022345678", IdentificacionEcuador.telefono("(02) 234-5678"));
        assertEquals("", IdentificacionEcuador.telefono("  "));
        for (String malo : new String[]{"abc", "099123456a", "12345", "0812345678", "099123456789"}) {
            assertThrows(IllegalArgumentException.class, () -> IdentificacionEcuador.telefono(malo), malo);
        }
    }
}
