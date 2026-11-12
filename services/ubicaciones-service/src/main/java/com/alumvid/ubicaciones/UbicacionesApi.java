package com.alumvid.ubicaciones;

import java.math.BigDecimal;
import java.util.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/ubicaciones")
class UbicacionesApi {
    record Space(@NotBlank @Size(max=100) String code,@Size(max=500) String description,@NotNull Boolean active) {}
    record Move(@NotNull UUID requestId,@NotNull UUID productId,UUID fromSpaceId,@NotNull UUID toSpaceId,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=15,fraction=12) BigDecimal quantity,
        @Size(max=200) List<@NotNull UUID> pieceIds,@NotBlank @Size(max=500) String reason) {}
    private final UbicacionesService service;
    UbicacionesApi(UbicacionesService service) {this.service=service;}
    @GetMapping("/spaces") Object list(@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {return service.spaces(q,page,size);}
    @PostMapping("/spaces") Object create(@Valid @RequestBody Space r,@AuthenticationPrincipal AuthClient.Identity actor) {return service.save(null,r,actor);}
    @PutMapping("/spaces/{id}") Object update(@PathVariable UUID id,@Valid @RequestBody Space r,@AuthenticationPrincipal AuthClient.Identity actor) {return service.save(id,r,actor);}
    @GetMapping("/spaces/{id}/contents") Object contents(@PathVariable UUID id) {return service.contents(id);}
    @GetMapping("/products") Object products(@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {return service.products(q,page,size);}
    @GetMapping("/products/{id}") Object product(@PathVariable UUID id) {return service.product(id);}
    @PostMapping("/moves") Object move(@Valid @RequestBody Move r,@AuthenticationPrincipal AuthClient.Identity actor) {return service.move(r,actor);}
    @GetMapping("/history") Object history(@RequestParam(required=false) UUID productId,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {return service.history(productId,page,size);}
}
