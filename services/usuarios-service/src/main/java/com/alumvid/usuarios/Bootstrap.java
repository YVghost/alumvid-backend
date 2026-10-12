package com.alumvid.usuarios;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.util.EnumSet;
import java.util.UUID;

@Component
public class Bootstrap implements CommandLineRunner {

    private final Users users;
    private final PasswordEncoder passwords;
    private final String identification;
    private final String name;
    private final String password;

    public Bootstrap(
            Users users,
            PasswordEncoder passwords,
            @Value("${app.master.identification}") String identification,
            @Value("${app.master.name}") String name,
            @Value("${app.master.password}") String password) {
        this.users = users;
        this.passwords = passwords;
        this.identification = identification;
        this.name = name;
        this.password = password;
    }

    @Override
    public void run(String... args) {
        if (identification.isBlank() || password.isBlank()) return;
        boolean exists = !users.db().queryForList("SELECT id FROM usuarios.app_user WHERE master = TRUE").isEmpty();
        if (exists) return;

        var u = new Users.User(
            UUID.randomUUID(),
            identification.trim(),
            "admin@alumvid.com",
            "+593999999999",
            name.trim(),
            passwords.encode(password),
            EnumSet.allOf(Users.Role.class),
            true,
            true,
            false // El bootstrap inicial ya tiene clave configurada
        );
        users.insert(u);
        users.audit(u.id(), u.id(), "SYSTEM_INIT", "Inicialización del Administrador Principal AlumVid");
    }
}
