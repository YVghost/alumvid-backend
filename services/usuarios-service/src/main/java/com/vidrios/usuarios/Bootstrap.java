package com.vidrios.usuarios;

import java.util.*;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.*;
import org.springframework.core.env.Environment;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.support.TransactionTemplate;

@Configuration
class Bootstrap {
    @Bean ApplicationRunner master(Users users, PasswordEncoder passwords, Environment env, TransactionTemplate tx) {
        return args -> tx.executeWithoutResult(status -> {
            // Bloqueo PostgreSQL compartido incluso con varias instancias arrancando.
            users.db.execute("SELECT pg_advisory_xact_lock(736241)");
            if (!users.db.queryForList("SELECT id FROM usuarios.app_user WHERE master=TRUE").isEmpty()) return;
            String id=env.getProperty("app.master.identification","");
            String name=env.getProperty("app.master.name","");
            String password=env.getProperty("app.master.password","");
            if (!id.matches("[A-Za-z0-9-]{3,30}") || name.isBlank() || name.length()>120 || password.length()<12 || password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>72)
                throw new IllegalStateException("Configura MASTER_IDENTIFICATION, MASTER_NAME y MASTER_PASSWORD (12 a 72 caracteres)");
            var u=new Users.User(UUID.randomUUID(),id,name,passwords.encode(password),Set.of(Users.Role.ADMINISTRADOR),true,true,true);
            users.insert(u); users.audit(u.id(),u.id(),"MASTER_CREATED","Administrador principal inicializado");
        });
    }
}
