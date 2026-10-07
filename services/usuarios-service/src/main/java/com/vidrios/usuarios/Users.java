package com.vidrios.usuarios;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
class Users {
    enum Role { ADMINISTRADOR, VENDEDOR, BODEGUERO, CHOFER }
    record User(UUID id, String identification, String fullName, String passwordHash,
                Set<Role> roles, boolean master, boolean active, boolean mustChangePassword) {
        View view() { return new View(id, identification, fullName, roles, master, active, mustChangePassword); }
        boolean admin() { return roles.contains(Role.ADMINISTRADOR); }
    }
    record View(UUID id, String identification, String fullName, Set<Role> roles,
                boolean master, boolean active, boolean mustChangePassword) {}
    final JdbcTemplate db;
    Users(JdbcTemplate db) { this.db = db; }
    private final org.springframework.jdbc.core.RowMapper<User> mapper = (r, n) -> new User(
        r.getObject("id", UUID.class), r.getString("identification"), r.getString("full_name"),
        r.getString("password_hash"), decode(r.getString("roles")), r.getBoolean("master"),
        r.getBoolean("active"), r.getBoolean("must_change_password"));
    static Set<Role> decode(String value) {
        Set<Role> roles = EnumSet.noneOf(Role.class);
        for (String role : value.split(",")) roles.add(Role.valueOf(role));
        return roles;
    }
    static String encode(Set<Role> roles) { return roles.stream().map(Enum::name).sorted().collect(java.util.stream.Collectors.joining(",")); }
    Optional<User> byIdentification(String id) {
        return db.query("SELECT * FROM usuarios.app_user WHERE identification=?", mapper, id).stream().findFirst();
    }
    User byId(UUID id) {
        return db.query("SELECT * FROM usuarios.app_user WHERE id=?", mapper, id).stream().findFirst()
            .orElseThrow(() -> new ApiError(404, "Usuario no encontrado"));
    }
    List<View> list() { return db.query("SELECT * FROM usuarios.app_user ORDER BY created_at, id", mapper).stream().map(User::view).toList(); }
    void insert(User u) {
        db.update("INSERT INTO usuarios.app_user(id,identification,full_name,password_hash,roles,master,active,must_change_password) VALUES (?,?,?,?,?,?,?,?)",
            u.id(),u.identification(),u.fullName(),u.passwordHash(),encode(u.roles()),u.master(),u.active(),u.mustChangePassword());
    }
    void audit(UUID actor, UUID target, String action, String detail) {
        db.update("INSERT INTO usuarios.audit_event(id,actor_id,target_id,action,detail) VALUES (?,?,?,?,?)",UUID.randomUUID(),actor,target,action,detail);
    }
    void revoke(UUID user) { db.update("DELETE FROM usuarios.auth_session WHERE user_id=?",user); }
}
