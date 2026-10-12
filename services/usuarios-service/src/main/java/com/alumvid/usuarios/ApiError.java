package com.alumvid.usuarios;

import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

public class ApiError extends RuntimeException {
    private final int status;

    public ApiError(int status, String message) {
        super(message);
        this.status = status;
    }

    public int status() {
        return status;
    }
}

@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(ApiError.class)
    public ResponseEntity<Map<String, Object>> handleApiError(ApiError e) {
        return ResponseEntity.status(e.status()).body(Map.of(
            "error", e.getMessage(),
            "message", e.getMessage(),
            "status", e.status()
        ));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidation(MethodArgumentNotValidException e) {
        String msg = e.getBindingResult().getFieldErrors().stream()
            .map(f -> f.getField() + ": " + f.getDefaultMessage())
            .findFirst().orElse("Datos inválidos");
        return ResponseEntity.badRequest().body(Map.of(
            "error", msg,
            "message", msg,
            "status", 400
        ));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> handleGeneral(Exception e) {
        return ResponseEntity.internalServerError().body(Map.of(
            "error", e.getMessage() != null ? e.getMessage() : "Error interno del servidor",
            "message", e.getMessage() != null ? e.getMessage() : "Error interno del servidor",
            "status", 500
        ));
    }
}
