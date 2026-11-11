package com.alumvid.retazos;

import java.math.BigDecimal;
import java.math.RoundingMode;

final class MaterialMath {
    static BigDecimal equivalent(BigDecimal measure,BigDecimal reference) {
        return measure.divide(reference,12,RoundingMode.HALF_UP);
    }
    static BigDecimal percentage(BigDecimal measure,BigDecimal reference) {
        return measure.multiply(new BigDecimal("100")).divide(reference,8,RoundingMode.HALF_UP);
    }
    static void positive(BigDecimal value,String field) {
        if(value==null || value.signum()<=0)throw new RetazosError(400,field+" debe ser mayor que cero");
    }
    static BigDecimal zero(BigDecimal value) { return value==null?BigDecimal.ZERO:value; }
    private MaterialMath() {}
}
