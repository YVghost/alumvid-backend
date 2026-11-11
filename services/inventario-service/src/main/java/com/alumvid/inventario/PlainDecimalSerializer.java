package com.alumvid.inventario;

import java.io.IOException;
import java.math.BigDecimal;
import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.databind.SerializerProvider;
import com.fasterxml.jackson.databind.ser.std.StdSerializer;

/** Mantiene el contrato decimal como texto, sin notación científica para 0E-12. */
public class PlainDecimalSerializer extends StdSerializer<BigDecimal> {
    public PlainDecimalSerializer() { super(BigDecimal.class); }
    @Override public void serialize(BigDecimal value,JsonGenerator generator,SerializerProvider provider) throws IOException {
        generator.writeString(value.toPlainString());
    }
}
