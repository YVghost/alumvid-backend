package com.alumvid.pedidos;

import java.math.BigDecimal;
import java.util.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/pedidos")
class PedidosApi {
    record Line(@NotNull UUID productId,
        @NotNull @DecimalMin(value="0",inclusive=false) @DecimalMax("999999") @Digits(integer=6,fraction=4) BigDecimal quantity,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal lengthM,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal widthCm,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal heightCm,
        @DecimalMin("0") @Digits(integer=6,fraction=4) BigDecimal wasteExtent,
        @NotNull @DecimalMin("0") @Digits(integer=10,fraction=2) BigDecimal unitPrice) {}
    record Check(@NotEmpty @Size(max=50) List<@Valid Line> lines) {}
    enum Delivery { RETIRO, ENTREGA }
    record Create(@NotNull UUID requestId,@Size(max=150) String clientName,
        @NotNull Delivery deliveryMode,@Size(max=500) String deliveryAddress,@Size(max=150) String receiverName,
        @Size(max=1000) String notes,@NotEmpty @Size(max=50) List<@Valid Line> lines,
        @NotNull UUID clientId,@NotNull @AssertTrue Boolean externallyConfirmed,@Size(max=100) String externalInvoiceReference) {
        Create(UUID requestId,String clientName,Delivery deliveryMode,String deliveryAddress,String receiverName,String notes,List<Line> lines) {
            this(requestId,clientName,deliveryMode,deliveryAddress,receiverName,notes,lines,null,true,"");
        }
    }
    record BatchLine(@NotNull UUID lineId,@NotNull @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal quantity) {}
    record Action(@NotNull UUID requestId,@NotBlank @Size(max=500) String reason,
        @Size(min=1,max=50) List<@Valid BatchLine> lines,@Size(max=150) String receiverName) {
        Action(UUID requestId,String reason) {this(requestId,reason,null,null);}
    }
    private final PedidosService service;
    private final AuthClient auth;
    PedidosApi(PedidosService service,AuthClient auth) {this.service=service;this.auth=auth;}
    @PostMapping("/auth/login") ResponseEntity<String> login(@RequestBody Map<String,Object> body) {return auth.forward("login",null,body);}
    @GetMapping("/auth/me") AuthClient.Identity me(@AuthenticationPrincipal AuthClient.Identity actor) {return actor;}
    @PostMapping("/auth/password") ResponseEntity<String> password(@RequestHeader("Authorization") String token,@RequestBody Map<String,Object> body) {return auth.forward("password",token,body);}
    @PostMapping("/auth/logout") ResponseEntity<String> logout(@RequestHeader("Authorization") String token) {return auth.forward("logout",token,null);}
    @GetMapping("/products") Object products(@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {return service.products(q,page,size);}
    @PostMapping("/availability") Object availability(@Valid @RequestBody Check r) {return service.availability(r.lines());}
    @PostMapping("/orders") Object create(@Valid @RequestBody Create r,@AuthenticationPrincipal AuthClient.Identity actor) {return service.create(r,actor);}
    @GetMapping("/orders") Object list(@RequestParam(defaultValue="") String state,@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {return service.list(state,q,page,size);}
    @GetMapping("/orders/{id}") Object get(@PathVariable UUID id) {return service.get(id);}
    @PostMapping("/orders/{id}/{action:confirm|retry|prepare|delay|resume|cancel|dispatch|deliver|receive-return}") Object action(@PathVariable UUID id,@PathVariable String action,@Valid @RequestBody Action r,@AuthenticationPrincipal AuthClient.Identity actor) {return service.action(id,action,r,actor);}
}
