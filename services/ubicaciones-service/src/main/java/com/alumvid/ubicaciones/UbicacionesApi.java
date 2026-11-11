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
    private final UbicacionesService service;private final AuthClient auth;
    UbicacionesApi(UbicacionesService service,AuthClient auth) {this.service=service;this.auth=auth;}
    @PostMapping("/auth/login") ResponseEntity<String> login(@RequestBody Map<String,Object> body) {return auth.forward("login",null,body);}
    @GetMapping("/auth/me") AuthClient.Identity me(@AuthenticationPrincipal AuthClient.Identity actor) {return actor;}
    @PostMapping("/auth/password") ResponseEntity<String> password(@RequestHeader("Authorization") String token,@RequestBody Map<String,Object> body) {return auth.forward("password",token,body);}
    @PostMapping("/auth/logout") ResponseEntity<String> logout(@RequestHeader("Authorization") String token) {return auth.forward("logout",token,null);}
    @GetMapping("/spaces") Object list(@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {return service.spaces(q,page,size);}
    @PostMapping("/spaces") Object create(@Valid @RequestBody Space r,@AuthenticationPrincipal AuthClient.Identity actor) {return service.save(null,r,actor);}
    @PutMapping("/spaces/{id}") Object update(@PathVariable UUID id,@Valid @RequestBody Space r,@AuthenticationPrincipal AuthClient.Identity actor) {return service.save(id,r,actor);}
    @GetMapping("/spaces/{id}/contents") Object contents(@PathVariable UUID id) {return service.contents(id);}
    @GetMapping("/products") Object products(@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {return service.products(q,page,size);}
    @GetMapping("/products/{id}") Object product(@PathVariable UUID id) {return service.product(id);}
    @PostMapping("/moves") Object move(@Valid @RequestBody Move r,@AuthenticationPrincipal AuthClient.Identity actor) {return service.move(r,actor);}
    @GetMapping("/history") Object history(@RequestParam(required=false) UUID productId,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {return service.history(productId,page,size);}
}
