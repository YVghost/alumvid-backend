package com.alumvid.usuarios;

import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** Registra eventos que deben persistir aunque la operación principal falle (p. ej. login rechazado). */
@Component
public class AuditLog {
    private final JdbcTemplate db;

    public AuditLog(JdbcTemplate db) {
        this.db = db;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void independent(UUID actor, UUID target, String action, String detail) {
        db.update(
            "INSERT INTO usuarios.audit_event(id, actor_id, target_id, action, detail) VALUES (?,?,?,?,?)",
            UUID.randomUUID(), actor, target, action, detail
        );
    }
}
