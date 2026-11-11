package com.alumvid.retazos;

import java.math.BigDecimal;
import java.util.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import static com.alumvid.retazos.RetazosRepository.map;

@RestController
@RequestMapping("/api/retazos")
class RetazosApi {
    enum Kind { ALUMINIO, VIDRIO }
    enum EntryMode { NUEVO, EXISTENTE }
    record FormatInput(@NotNull Kind kind,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal fullLengthM,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal fullWidthCm,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal fullHeightCm) {}
    record RegisterInput(@NotNull UUID requestId,@NotNull EntryMode mode,@NotNull @Min(1) @Max(200) Integer quantity,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal lengthM,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal widthCm,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal heightCm,
        @Size(max=100) String location,@NotBlank @Size(max=500) String reason) {}
    record CutInput(@NotNull UUID requestId,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal usedLengthM,
        @DecimalMin(value="0",inclusive=false) @Digits(integer=6,fraction=4) BigDecimal usedWidthCm,
        @DecimalMin("0") @Digits(integer=6,fraction=4) BigDecimal wasteLengthM,
        @DecimalMin("0") @Digits(integer=6,fraction=4) BigDecimal wasteWidthCm,
        @NotBlank @Size(max=500) String reason) {}
    record ReasonInput(@NotNull UUID requestId,@NotBlank @Size(max=500) String reason) {}
    record ReconcileInput(@NotNull UUID requestId,@NotNull @DecimalMin("0") @Digits(integer=15,fraction=12) BigDecimal unallocatedUnits,
        @NotBlank @Size(max=500) String reason) {}
    private final RetazosService service;
    private final RetazosRepository repository;
    private final AuthClient auth;
    RetazosApi(RetazosService service,RetazosRepository repository,AuthClient auth) { this.service=service;this.repository=repository;this.auth=auth; }
    @PostMapping("/auth/login") ResponseEntity<String> login(@RequestBody Map<String,Object> body) { return auth.forward("login",null,body); }
    @GetMapping("/auth/me") AuthClient.Identity me(@AuthenticationPrincipal AuthClient.Identity actor) { return actor; }
    @PostMapping("/auth/password") ResponseEntity<String> password(@RequestHeader("Authorization") String token,@RequestBody Map<String,Object> body) { return auth.forward("password",token,body); }
    @PostMapping("/auth/logout") ResponseEntity<String> logout(@RequestHeader("Authorization") String token) { return auth.forward("logout",token,null); }
    private void page(int page,int size) { if(page<0||size<1||size>100)throw new RetazosError(400,"Página >=0 y tamaño entre 1 y 100"); }
    @GetMapping("/products") Map<String,Object> products(@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {
        page(page,size);if(q.length()>150)throw new RetazosError(400,"Filtro demasiado largo");
        String filter=q.trim().toLowerCase(Locale.ROOT);
        var items=repository.db().queryForList("SELECT p.id,p.code,p.name,p.stock,p.unit,p.active,p.pieces_managed AS \"piecesManaged\",f.kind FROM inventario.product p LEFT JOIN retazos.material_format f ON f.product_id=p.id WHERE POSITION(? IN LOWER(p.code||' '||p.name))>0 ORDER BY p.name,p.id LIMIT ? OFFSET ?",filter,size,(long)page*size);
        long total=repository.db().queryForObject("SELECT count(*) FROM inventario.product WHERE POSITION(? IN LOWER(code||' '||name))>0",Long.class,filter);
        return map("items",items,"total",total,"page",page,"size",size);
    }
    @PutMapping("/products/{id}/format") Map<String,Object> configure(@PathVariable UUID id,@Valid @RequestBody FormatInput body,@AuthenticationPrincipal AuthClient.Identity actor) { return service.configure(id,body,actor); }
    @GetMapping("/products/{id}/summary") Map<String,Object> summary(@PathVariable UUID id) { return service.summary(id); }
    @GetMapping("/products/{id}/pieces") Map<String,Object> pieces(@PathVariable UUID id,@RequestParam(defaultValue="DISPONIBLE") String state,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {
        page(page,size);
        if(!Set.of("","DISPONIBLE","TRANSFORMADO","CONSUMIDO","DESCARTADO","PREPARADO","ENTREGADO").contains(state))throw new RetazosError(400,"Estado inválido");
        var format=repository.format(id);long total=repository.db().queryForObject("SELECT count(*) FROM retazos.piece WHERE product_id=? AND (?='' OR state=?)",Long.class,id,state,state);
        return map("items",repository.pieces(id,state,size,(long)page*size).stream().map(p->p.view(format)).toList(),"total",total,"page",page,"size",size);
    }
    @PostMapping("/products/{id}/pieces") Map<String,Object> register(@PathVariable UUID id,@Valid @RequestBody RegisterInput body,@AuthenticationPrincipal AuthClient.Identity actor) { return service.register(id,body,actor); }
    @PostMapping("/products/{id}/pieces/{pieceId}/cut") Map<String,Object> cut(@PathVariable UUID id,@PathVariable UUID pieceId,@Valid @RequestBody CutInput body,@AuthenticationPrincipal AuthClient.Identity actor) { return service.cut(id,pieceId,body,actor); }
    @PostMapping("/products/{id}/pieces/{pieceId}/discard") Map<String,Object> discard(@PathVariable UUID id,@PathVariable UUID pieceId,@Valid @RequestBody ReasonInput body,@AuthenticationPrincipal AuthClient.Identity actor) { return service.discard(id,pieceId,body,actor); }
    @PostMapping("/products/{id}/reconcile") Map<String,Object> reconcile(@PathVariable UUID id,@Valid @RequestBody ReconcileInput body,@AuthenticationPrincipal AuthClient.Identity actor) { return service.reconcile(id,body,actor); }
    @GetMapping("/products/{id}/suggestions") List<Map<String,Object>> suggestions(@PathVariable UUID id,@RequestParam BigDecimal extent) {
        MaterialMath.positive(extent,"Medida requerida");var f=repository.format(id);
        String column=f.kind().equals("ALUMINIO")?"length_m":"width_cm";
        BigDecimal full=f.kind().equals("ALUMINIO")?f.fullLengthM():f.fullWidthCm();
        return repository.db().queryForList("SELECT id,length_m AS \"lengthM\",width_cm AS \"widthCm\",height_cm AS \"heightCm\",location FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE' AND NOT EXISTS(SELECT 1 FROM inventario.stock_reservation r WHERE r.piece_id=retazos.piece.id AND r.state='ACTIVA') AND "+column+">=? ORDER BY ("+column+"=?),"+column+",created_at,id LIMIT 100",id,extent,full);
    }
    @GetMapping("/products/{id}/operations") Map<String,Object> history(@PathVariable UUID id,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {
        page(page,size);repository.format(id);
        var items=repository.db().queryForList("SELECT id,request_id AS \"requestId\",action,actor_name AS \"actorName\",reason,result->>'stockBefore' AS \"stockBefore\",result->>'stockAfter' AS \"stockAfter\",result->>'inventoryDelta' AS \"inventoryDelta\",created_at AS \"createdAt\" FROM retazos.operation WHERE product_id=? ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?",id,size,(long)page*size);
        long total=repository.db().queryForObject("SELECT count(*) FROM retazos.operation WHERE product_id=?",Long.class,id);
        return map("items",items,"total",total,"page",page,"size",size);
    }
}
