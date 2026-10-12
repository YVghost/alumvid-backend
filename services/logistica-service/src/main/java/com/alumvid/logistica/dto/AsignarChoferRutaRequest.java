package com.alumvid.logistica.dto;

import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AsignarChoferRutaRequest {
    @NotNull(message = "El ID del chofer es obligatorio")
    private UUID choferId;
}
