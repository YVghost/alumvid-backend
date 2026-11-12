package com.alumvid.logistica.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ModificarCargaRequest {
    @NotEmpty(message = "La carga no puede quedar vacía; quita la parada si ya no se entrega")
    @Valid
    private List<LineaCargaRequest> lineas;
}
