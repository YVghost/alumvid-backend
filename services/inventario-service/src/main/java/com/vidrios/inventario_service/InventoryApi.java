package com.vidrios.inventario_service;

import java.math.BigDecimal;
import java.util.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
class InventoryApi {
    record ProductInput(@NotBlank @Pattern(regexp="[A-Za-z0-9._-]{1,40}") String code,
        @NotBlank @Size(max=150) String name,@NotBlank @Size(max=60) String category,@NotNull InventoryRepository.Unit unit,
        @Size(max=500) String description,@Size(max=150) String supplier,@Size(max=60) String externalCode,
        @Size(max=100) String location,@NotNull @DecimalMin("0") @Digits(integer=15,fraction=4) BigDecimal minStock,@NotNull Boolean active) {}
    record MovementInput(@NotNull UUID requestId,@NotNull InventoryRepository.MovementType type,
        @NotNull @DecimalMin("0") @Digits(integer=15,fraction=4) BigDecimal quantity,
        @NotBlank @Size(max=500) String reason,@Size(max=100) String reference) {}
    private final InventoryRepository products;private final InventoryService service;private final AuthClient auth;
    InventoryApi(InventoryRepository products,InventoryService service,AuthClient auth) { this.products=products;this.service=service;this.auth=auth; }
    @PostMapping("/auth/login") ResponseEntity<String> login(@RequestBody Map<String,Object> body) { return auth.forward("login",null,body); }
    @GetMapping("/auth/me") AuthClient.Identity me(@AuthenticationPrincipal AuthClient.Identity actor) { return actor; }
    @PostMapping("/auth/password") ResponseEntity<String> password(@RequestHeader("Authorization") String token,@RequestBody Map<String,Object> body) { return auth.forward("password",token,body); }
    @PostMapping("/auth/logout") ResponseEntity<String> logout(@RequestHeader("Authorization") String token) { return auth.forward("logout",token,null); }
    private void page(int page,int size) { if(page<0 || size<1 || size>100) throw new InventoryError(400,"Página >=0 y tamaño entre 1 y 100"); }
    @GetMapping("/products") InventoryRepository.Page<InventoryRepository.Product> list(
        @RequestParam(defaultValue="") String q,@RequestParam(defaultValue="") String category,
        @RequestParam(defaultValue="false") boolean includeInactive,@RequestParam(defaultValue="false") boolean lowStock,
        @RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {
        page(page,size);if(q.length()>150||category.length()>60)throw new InventoryError(400,"Filtro demasiado largo");
        return products.list(q.trim(),category.trim().toUpperCase(Locale.ROOT),includeInactive,lowStock,page,size);
    }
    @GetMapping("/products/{id}") InventoryRepository.Product get(@PathVariable UUID id) { return products.get(id,false); }
    @PostMapping("/products") @ResponseStatus(HttpStatus.CREATED)
    InventoryRepository.Product create(@Valid @RequestBody ProductInput body,@AuthenticationPrincipal AuthClient.Identity actor) { return service.create(body,actor); }
    @PutMapping("/products/{id}") InventoryRepository.Product update(@PathVariable UUID id,@Valid @RequestBody ProductInput body,@AuthenticationPrincipal AuthClient.Identity actor) { return service.update(id,body,actor); }
    @PostMapping("/products/{id}/movements") InventoryRepository.Movement move(@PathVariable UUID id,@Valid @RequestBody MovementInput body,@AuthenticationPrincipal AuthClient.Identity actor) { return service.move(id,body,actor); }
    @GetMapping("/products/{id}/movements") InventoryRepository.Page<InventoryRepository.Movement> movements(@PathVariable UUID id,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) { page(page,size);products.get(id,false);return products.movements(id,page,size); }
    @GetMapping("/products/{id}/history") List<Map<String,Object>> history(@PathVariable UUID id,@AuthenticationPrincipal AuthClient.Identity actor) {
        if(!actor.has("ADMINISTRADOR"))throw new InventoryError(403,"Solo administradores pueden consultar cambios del catálogo");
        products.get(id,false);return products.history(id);
    }
}
