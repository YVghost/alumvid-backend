package com.alumvid.logistica.controller;

import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

/** Respuestas de error con {"status","message"}, igual que el resto de servicios. */
@RestControllerAdvice
@Slf4j
public class ManejadorErrores {

    private static ResponseEntity<Map<String, Object>> cuerpo(HttpStatus status, String mensaje) {
        return ResponseEntity.status(status).body(Map.of("status", status.value(), "message", mensaje == null ? status.getReasonPhrase() : mensaje));
    }

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<Map<String, Object>> estado(ResponseStatusException e) {
        var status = HttpStatus.resolve(e.getStatusCode().value());
        return cuerpo(status != null ? status : HttpStatus.INTERNAL_SERVER_ERROR, e.getReason());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<Map<String, Object>> validacion(MethodArgumentNotValidException e) {
        var error = e.getBindingResult().getFieldErrors().stream().findFirst();
        return cuerpo(HttpStatus.BAD_REQUEST, error.map(f -> f.getDefaultMessage()).orElse("Datos inválidos"));
    }

    @ExceptionHandler(IllegalStateException.class)
    ResponseEntity<Map<String, Object>> conflicto(IllegalStateException e) {
        return cuerpo(HttpStatus.CONFLICT, e.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, Object>> invalido(IllegalArgumentException e) {
        return cuerpo(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<Map<String, Object>> inesperado(Exception e) {
        log.error("Error no controlado en logística", e);
        return cuerpo(HttpStatus.INTERNAL_SERVER_ERROR, "Error interno en logística");
    }
}
