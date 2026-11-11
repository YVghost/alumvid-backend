package com.alumvid.pedidos;

import java.util.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import static com.alumvid.pedidos.AvailabilityPlanner.map;

@RestController
@RequestMapping("/api/pedidos/clients")
class ClientApi {
    record Input(@NotBlank @Size(max=150) String name,@Size(max=40) String identification,@Size(max=40) String phone,
        @Email @Size(max=150) String email,@Size(max=500) String address,@NotNull Boolean active) {}
    private final JdbcTemplate db;
    ClientApi(JdbcTemplate db) {this.db=db;}
    @GetMapping Object list(@RequestParam(defaultValue="") String q,@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size,@RequestParam(defaultValue="false") boolean includeInactive) {
        if(page<0||size<1||size>100||q.length()>150)throw new PedidosError(400,"Paginacion o filtro invalido");
        String where=" WHERE (? OR active) AND POSITION(? IN lower(name||' '||COALESCE(identification,'')||' '||phone))>0";
        return map("items",db.queryForList("SELECT * FROM pedidos.client"+where+" ORDER BY name,id LIMIT ? OFFSET ?",includeInactive,q.toLowerCase(Locale.ROOT),size,(long)page*size),"total",db.queryForObject("SELECT count(*) FROM pedidos.client"+where,Long.class,includeInactive,q.toLowerCase(Locale.ROOT)),"page",page,"size",size);
    }
    @PostMapping @Transactional Object create(@Valid @RequestBody Input r,@AuthenticationPrincipal AuthClient.Identity actor) {return save(UUID.randomUUID(),r,actor,true);}
    @PutMapping("/{id}") @Transactional Object update(@PathVariable UUID id,@Valid @RequestBody Input r,@AuthenticationPrincipal AuthClient.Identity actor) {return save(id,r,actor,false);}
    private Object save(UUID id,Input r,AuthClient.Identity actor,boolean create) {
        if(!actor.has("ADMINISTRADOR")&&!actor.has("VENDEDOR"))throw new PedidosError(403,"Sin permisos para administrar clientes");
        String identification=PedidosService.text(r.identification());if(identification.isEmpty())identification=null;
        if(create)db.update("INSERT INTO pedidos.client(id,name,identification,phone,email,address,active) VALUES (?,?,?,?,?,?,?)",id,r.name().trim(),identification,PedidosService.text(r.phone()),PedidosService.text(r.email()),PedidosService.text(r.address()),r.active());
        else if(db.update("UPDATE pedidos.client SET name=?,identification=?,phone=?,email=?,address=?,active=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",r.name().trim(),identification,PedidosService.text(r.phone()),PedidosService.text(r.email()),PedidosService.text(r.address()),r.active(),id)==0)throw new PedidosError(404,"Cliente no encontrado");
        return db.queryForMap("SELECT * FROM pedidos.client WHERE id=?",id);
    }
}
