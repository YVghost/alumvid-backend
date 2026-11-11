package com.alumvid.pedidos;

import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.bind.MethodArgumentNotValidException;

class PedidosError extends RuntimeException {
    final int status;
    PedidosError(int status,String message) { super(message);this.status=status; }
}
@RestControllerAdvice
class PedidosErrors {
    @ExceptionHandler(PedidosError.class) ResponseEntity<?> error(PedidosError e) {
        return ResponseEntity.status(e.status).body(Map.of("message",e.getMessage()));
    }
    @ExceptionHandler(MethodArgumentNotValidException.class) ResponseEntity<?> validation(MethodArgumentNotValidException e) {
        return ResponseEntity.badRequest().body(Map.of("message","Revisa las medidas y los campos requeridos","errors",
            e.getBindingResult().getFieldErrors().stream().map(f->f.getField()+": "+f.getDefaultMessage()).toList()));
    }
    @ExceptionHandler({org.springframework.http.converter.HttpMessageNotReadableException.class,org.springframework.web.method.annotation.MethodArgumentTypeMismatchException.class})
    ResponseEntity<?> invalid() { return ResponseEntity.badRequest().body(Map.of("message","Solicitud inválida")); }
    @ExceptionHandler(org.springframework.dao.DataIntegrityViolationException.class)
    ResponseEntity<?> conflict() { return ResponseEntity.status(409).body(Map.of("message","Conflicto de datos. Actualiza el desglose antes de reintentar.")); }
    @ExceptionHandler({org.springframework.dao.DataAccessResourceFailureException.class,org.springframework.transaction.CannotCreateTransactionException.class})
    ResponseEntity<?> unavailable() { return ResponseEntity.status(503).body(Map.of("message","La base de datos no está disponible")); }
}
