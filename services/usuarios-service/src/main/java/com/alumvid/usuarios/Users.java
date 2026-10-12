package com.alumvid.usuarios;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class Users {
    public enum Role { ADMINISTRADOR, VENDEDOR, BODEGUERO, CHOFER }

    public record User(
        UUID id,
        String identification,
        String email,
        String telefono,
        String fullName,
        String passwordHash,
        Set<Role> roles,
        boolean master,
        boolean active,
        boolean mustChangePassword
    ) {
        public View view() {
            return new View(id, identification, email, telefono, fullName, roles, master, active, mustChangePassword);
        }
        public boolean admin() {
            return roles.contains(Role.ADMINISTRADOR);
        }
    }

    public record View(
        UUID id,
        String identification,
        String email,
        String telefono,
        String fullName,
        Set<Role> roles,
        boolean master,
        boolean active,
        boolean mustChangePassword
    ) {}

    private final JdbcTemplate db;

    public Users(JdbcTemplate db) {
        this.db = db;
    }

    public JdbcTemplate db() {
        return db;
    }

    private final org.springframework.jdbc.core.RowMapper<User> mapper = (r, n) -> new User(
        r.getObject("id", UUID.class),
        r.getString("identification"),
        r.getString("email"),
        r.getString("telefono"),
        r.getString("full_name"),
        r.getString("password_hash"),
        decode(r.getString("roles")),
        r.getBoolean("master"),
        r.getBoolean("active"),
        r.getBoolean("must_change_password")
    );

    public static Set<Role> decode(String value) {
        if (value == null || value.isBlank()) return EnumSet.noneOf(Role.class);
        Set<Role> roles = EnumSet.noneOf(Role.class);
        for (String role : value.split(",")) {
            try {
                roles.add(Role.valueOf(role.trim()));
            } catch (Exception ignored) {}
        }
        return roles;
    }

    public static String encode(Set<Role> roles) {
        if (roles == null || roles.isEmpty()) return "";
        return roles.stream().map(Enum::name).sorted().collect(java.util.stream.Collectors.joining(","));
    }

    public Optional<User> byIdentification(String id) {
        return db.query("SELECT * FROM usuarios.app_user WHERE identification = ?", mapper, id).stream().findFirst();
    }

    public Optional<User> byIdentificationOrEmail(String loginInput) {
        return db.query("SELECT * FROM usuarios.app_user WHERE identification = ? OR email = ?", mapper, loginInput, loginInput).stream().findFirst();
    }

    public User byId(UUID id) {
        return db.query("SELECT * FROM usuarios.app_user WHERE id = ?", mapper, id).stream().findFirst()
            .orElseThrow(() -> new ApiError(404, "Usuario no encontrado"));
    }

    public List<View> list() {
        return db.query("SELECT * FROM usuarios.app_user ORDER BY created_at, id", mapper).stream().map(User::view).toList();
    }

    public void insert(User u) {
        db.update(
            "INSERT INTO usuarios.app_user(id, identification, email, telefono, full_name, password_hash, roles, master, active, must_change_password) VALUES (?,?,?,?,?,?,?,?,?,?)",
            u.id(), u.identification(), u.email(), u.telefono(), u.fullName(), u.passwordHash(), encode(u.roles()), u.master(), u.active(), u.mustChangePassword()
        );
    }

    public void audit(UUID actor, UUID target, String action, String detail) {
        db.update(
            "INSERT INTO usuarios.audit_event(id, actor_id, target_id, action, detail) VALUES (?,?,?,?,?)",
            UUID.randomUUID(), actor, target, action, detail
        );
    }

    public void revoke(UUID user) {
        db.update("DELETE FROM usuarios.auth_session WHERE user_id = ?", user);
    }
}
