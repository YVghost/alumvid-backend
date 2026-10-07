package com.vidrios.inventario_service;

import java.math.BigDecimal;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class InventoryService {
    private final InventoryRepository products;
    InventoryService(InventoryRepository products) { this.products=products; }
    private void admin(AuthClient.Identity actor) { if(!actor.has("ADMINISTRADOR")) throw new InventoryError(403,"Solo administradores pueden realizar esta operación"); }
    @Transactional
    public InventoryRepository.Product create(InventoryApi.ProductInput r,AuthClient.Identity actor) {
        admin(actor);
        if(!r.active()) throw new InventoryError(400,"Un producto nuevo debe estar activo");
        UUID id=UUID.randomUUID();products.insert(id,r);
        var product=products.get(id,false);products.audit(id,actor,"PRODUCT_CREATED",product.toString());return product;
    }
    @Transactional
    public InventoryRepository.Product update(UUID id,InventoryApi.ProductInput r,AuthClient.Identity actor) {
        admin(actor);var before=products.get(id,true);
        if(!before.code().equals(r.code().trim().toUpperCase(Locale.ROOT))) throw new InventoryError(409,"El código de un producto no se puede cambiar");
        if(before.unit()!=r.unit() && products.hasMovements(id)) throw new InventoryError(409,"No puedes cambiar la unidad de un producto con movimientos");
        if(!r.active() && before.stock().signum()!=0) throw new InventoryError(409,"El stock debe ser cero antes de desactivar el producto");
        products.update(id,r);var after=products.get(id,false);
        products.audit(id,actor,"PRODUCT_UPDATED","Anterior: "+before+"; Nuevo: "+after);return after;
    }
    @Transactional
    public InventoryRepository.Movement move(UUID id,InventoryApi.MovementInput r,AuthClient.Identity actor) {
        if(!actor.has("ADMINISTRADOR")&&!actor.has("BODEGUERO")) throw new InventoryError(403,"No tienes permisos para registrar movimientos");
        if(r.type()==InventoryRepository.MovementType.AJUSTE) admin(actor);
        var product=products.get(id,true);
        var existing=products.request(id,r.requestId());
        if(existing.isPresent()) {
            var m=existing.get();
            if(m.type()!=r.type() || m.quantity().compareTo(r.quantity())!=0 || !m.reason().equals(r.reason().trim()) || !m.reference().equals(InventoryRepository.text(r.reference())) || !m.actorId().equals(actor.id()))
                throw new InventoryError(409,"Este identificador de solicitud ya se usó con otros datos");
            return m;
        }
        if(!product.active()) throw new InventoryError(409,"El producto está inactivo");
        if(r.type()!=InventoryRepository.MovementType.AJUSTE && r.quantity().signum()<=0) throw new InventoryError(400,"La cantidad debe ser mayor que cero");
        BigDecimal delta=switch(r.type()) {
            case INGRESO->r.quantity();case SALIDA->r.quantity().negate();case AJUSTE->r.quantity().subtract(product.stock());
        };
        var after=product.stock().add(delta);
        if(after.signum()<0) throw new InventoryError(409,"Stock insuficiente para registrar la salida");
        if(after.precision()-after.scale()>15) throw new InventoryError(400,"El saldo supera la capacidad permitida");
        if(delta.signum()==0) throw new InventoryError(400,"El ajuste no modifica las existencias");
        products.movement(UUID.randomUUID(),r,product,delta,after,actor);
        return products.request(id,r.requestId()).orElseThrow();
    }
}
