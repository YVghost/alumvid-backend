package com.alumvid.logistica.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class LineaCargaRequest {
    @NotNull
    private UUID lineId;
    @NotNull
    @DecimalMin(value = "0", inclusive = false, message = "La cantidad debe ser mayor que cero")
    private BigDecimal quantity;
}
