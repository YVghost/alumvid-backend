package com.vidrios.inventario_service;

import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.dao.DataIntegrityViolationException;

class InventoryError extends RuntimeException {
    final int status;
    InventoryError(int status,String message) { super(message); this.status=status; }
}
@RestControllerAdvice
class InventoryErrors {
    @ExceptionHandler(InventoryError.class) ResponseEntity<?> error(InventoryError e) {
        return ResponseEntity.status(e.status).body(Map.of("message",e.getMessage()));
    }
    @ExceptionHandler(MethodArgumentNotValidException.class) ResponseEntity<?> invalid(MethodArgumentNotValidException e) {
        return ResponseEntity.badRequest().body(Map.of("message","Revisa los campos","errors",e.getBindingResult().getFieldErrors().stream().map(f->f.getField()+": "+f.getDefaultMessage()).toList()));
    }
    @ExceptionHandler(DataIntegrityViolationException.class) ResponseEntity<?> conflict() {
        return ResponseEntity.status(409).body(Map.of("message","Código duplicado o conflicto de datos"));
    }
    @ExceptionHandler({org.springframework.http.converter.HttpMessageNotReadableException.class,org.springframework.web.method.annotation.MethodArgumentTypeMismatchException.class})
    ResponseEntity<?> malformed() { return ResponseEntity.badRequest().body(Map.of("message","Solicitud inválida")); }
    @ExceptionHandler(org.springframework.dao.DataAccessResourceFailureException.class)
    ResponseEntity<?> unavailable() { return ResponseEntity.status(503).body(Map.of("message","La base de inventario no está disponible. Intenta nuevamente.")); }
}
