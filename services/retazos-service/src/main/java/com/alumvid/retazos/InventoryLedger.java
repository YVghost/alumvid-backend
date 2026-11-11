package com.alumvid.retazos;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.springframework.stereotype.Component;

/** Adaptador de la base compartida: stock y piezas participan en la MISMA transacción PostgreSQL.
 * No hace llamadas HTTP con efectos laterales dentro de una transacción local. */
@Component
class InventoryLedger {
    private final RetazosRepository repository;
    InventoryLedger(RetazosRepository repository) { this.repository=repository; }
    UUID apply(UUID productId,UUID requestId,BigDecimal before,BigDecimal after,String reason,AuthClient.Identity actor,boolean adjustment) {
        var delta=after.subtract(before);
        if(after.signum()<0 || after.precision()-after.scale()>15)throw new RetazosError(409,"Saldo fuera de los límites del inventario");
        if(delta.signum()==0)return null;
        UUID movementId=UUID.randomUUID();
        String type=adjustment?"AJUSTE":delta.signum()>0?"INGRESO":"SALIDA";
        BigDecimal quantity=adjustment?after:delta.abs();
        UUID inventoryRequest=UUID.nameUUIDFromBytes(("retazos:"+productId+":"+requestId).getBytes(StandardCharsets.UTF_8));
        repository.db().update("INSERT INTO inventario.movement(id,request_id,product_id,type,quantity,delta,stock_before,stock_after,reason,reference,actor_id,actor_name) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            movementId,inventoryRequest,productId,type,quantity,delta,before,after,reason,"retazos:"+requestId,actor.id(),actor.fullName());
        repository.db().update("UPDATE inventario.product SET stock=?,updated_at=CURRENT_TIMESTAMP WHERE id=?",after,productId);
        return movementId;
    }
}
