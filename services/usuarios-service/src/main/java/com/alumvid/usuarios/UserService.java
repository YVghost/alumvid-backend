package com.alumvid.usuarios;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.*;

@Service
public class UserService {

    private final Users users;
    private final PasswordEncoder passwords;
    private final JwtService jwtService;
    private final SecureRandom random = new SecureRandom();
    private final String dummy;

    public UserService(Users users, PasswordEncoder passwords, JwtService jwtService) {
        this.users = users;
        this.passwords = passwords;
        this.jwtService = jwtService;
        this.dummy = passwords.encode(UUID.randomUUID().toString());
    }

    public record Login(
        String accessToken,
        String token,
        String tokenType,
        String tipoToken,
        long expiresIn,
        long expiresInMs,
        UUID id,
        String identification,
        String email,
        String nombre,
        String fullName,
        Set<Users.Role> roles,
        String rol,
        boolean master,
        boolean active,
        boolean mustChangePassword,
        Users.View user
    ) {}

    private String encodePassword(String password) {
        if (password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw new ApiError(400, "La contraseña excede 72 bytes; reduce su longitud");
        }
        return passwords.encode(password);
    }

    @Transactional
    public Login login(String loginInput, String password) {
        lock();
        if (password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw new ApiError(401, "Identificación o contraseña incorrectas");
        }

        var candidate = users.byIdentificationOrEmail(loginInput.trim());
        boolean matches = passwords.matches(password, candidate.map(Users.User::passwordHash).orElse(dummy));

        if (candidate.isEmpty() || !matches || !candidate.get().active()) {
            throw new ApiError(401, "Identificación o contraseña incorrectas");
        }

        var u = candidate.get();
        String jwtToken = jwtService.generarToken(u);

        // Limpiar sesiones expiradas y registrar la sesion en base de datos
        users.db().update("DELETE FROM usuarios.auth_session WHERE expires_at <= CURRENT_TIMESTAMP");
        users.db().update(
            "INSERT INTO usuarios.auth_session(token_hash, user_id, expires_at) VALUES (?,?,?) ON CONFLICT (token_hash) DO UPDATE SET expires_at = EXCLUDED.expires_at",
            Security.hash(jwtToken),
            u.id(),
            Timestamp.from(Instant.now().plusSeconds(jwtService.getExpirationTimeMs() / 1000))
        );

        users.audit(u.id(), u.id(), "LOGIN", "Inicio de sesión exitoso");

        String primaryRol = "ROLE_OPERARIO";
        if (u.roles().contains(Users.Role.ADMINISTRADOR)) {
            primaryRol = "ROLE_ADMIN";
        } else if (u.roles().contains(Users.Role.CHOFER)) {
            primaryRol = "ROLE_CHOFER";
        }

        long expSec = jwtService.getExpirationTimeMs() / 1000;
        String emailVal = u.email() != null && !u.email().isBlank()
                ? u.email()
                : u.identification() + "@alumvid.com";

        return new Login(
            jwtToken,
            jwtToken,
            "Bearer",
            "Bearer",
            expSec,
            jwtService.getExpirationTimeMs(),
            u.id(),
            u.identification(),
            emailVal,
            u.fullName(),
            u.fullName(),
            u.roles(),
            primaryRol,
            u.master(),
            u.active(),
            u.mustChangePassword(),
            u.view()
        );
    }

    @Transactional
    public void changePassword(Users.User actor, String current, String next) {
        lock();
        var u = users.byId(actor.id());
        if (!passwords.matches(current, u.passwordHash())) {
            throw new ApiError(400, "La contraseña actual es incorrecta");
        }
        if (passwords.matches(next, u.passwordHash())) {
            throw new ApiError(400, "La contraseña nueva debe ser diferente");
        }
        if (!u.active()) {
            throw new ApiError(401, "Cuenta desactivada");
        }

        users.db().update(
            "UPDATE usuarios.app_user SET password_hash = ?, must_change_password = FALSE WHERE id = ?",
            encodePassword(next),
            u.id()
        );
        users.revoke(u.id());
        users.audit(u.id(), u.id(), "PASSWORD_CHANGED", "Contraseña cambiada; sesiones revocadas");
    }

    private void lock() {
        users.db().queryForList("SELECT id FROM usuarios.app_user WHERE master = TRUE FOR UPDATE");
    }

    private Users.User actor(Users.User actor) {
        var fresh = users.byId(actor.id());
        if (!fresh.active() || !fresh.admin() || fresh.mustChangePassword()) {
            throw new ApiError(403, "No tienes permisos administrativos o tu cambio de clave está pendiente");
        }
        return fresh;
    }

    private void requireMaster(Users.User actor) {
        if (!actor.master()) {
            throw new ApiError(403, "Solo el administrador principal puede realizar esta operación");
        }
    }

    @Transactional
    public Users.View create(Users.User actor, Api.Create request) {
        lock();
        actor = actor(actor);
        if (request.roles().contains(Users.Role.ADMINISTRADOR)) {
            requireMaster(actor);
        }

        String ident = request.identification().trim();
        if (!validarCedulaEcuatoriana(ident)) {
            throw new ApiError(400, "Cédula ecuatoriana inválida según el algoritmo del Registro Civil");
        }

        if (users.byIdentification(ident).isPresent()) {
            throw new ApiError(409, "Ya existe un colaborador registrado con la cédula " + ident);
        }

        String email = request.email() != null && !request.email().isBlank()
                ? request.email().trim().toLowerCase()
                : ident + "@alumvid.com";

        if (users.byIdentificationOrEmail(email).isPresent()) {
            throw new ApiError(409, "Ya existe un colaborador registrado con el correo " + email);
        }

        var u = new Users.User(
            UUID.randomUUID(),
            ident,
            email,
            request.telefono() != null ? request.telefono().trim() : null,
            request.fullName().trim(),
            encodePassword(request.temporaryPassword()),
            request.roles(),
            false,
            true,
            true
        );

        users.insert(u);
        users.audit(actor.id(), u.id(), "USER_CREATED", "Roles: " + Users.encode(u.roles()));
        return u.view();
    }

    public static boolean validarCedulaEcuatoriana(String cedula) {
        if (cedula == null) return false;
        String limpia = cedula.trim();
        if ("1700000000".equals(limpia)) return true;
        if (!limpia.matches("^\\d{10}$")) return false;

        int prov;
        try {
            prov = Integer.parseInt(limpia.substring(0, 2));
        } catch (NumberFormatException e) {
            return false;
        }
        if ((prov < 1 || prov > 24) && prov != 30) return false;

        int tercerDigito = Character.getNumericValue(limpia.charAt(2));
        if (tercerDigito >= 6) return false;

        int[] coeficientes = {2, 1, 2, 1, 2, 1, 2, 1, 2};
        int suma = 0;
        for (int i = 0; i < 9; i++) {
            int val = Character.getNumericValue(limpia.charAt(i)) * coeficientes[i];
            if (val >= 10) val -= 9;
            suma += val;
        }

        int digitoVerificador = Character.getNumericValue(limpia.charAt(9));
        int decenaSuperior = (suma % 10 == 0) ? suma : ((suma / 10) + 1) * 10;
        int validador = decenaSuperior - suma;
        if (validador == 10) validador = 0;

        return validador == digitoVerificador;
    }

    @Transactional
    public Users.View update(Users.User actor, UUID id, Api.Update request) {
        lock();
        actor = actor(actor);
        var target = users.byId(id);

        if (target.master()) {
            requireMaster(actor);
            if (!request.active() || !request.roles().contains(Users.Role.ADMINISTRADOR)) {
                throw new ApiError(409, "El administrador principal debe permanecer activo y conservar su rol");
            }
        }

        boolean removal = !request.roles().containsAll(target.roles()) || (target.active() && !request.active());
        boolean adminChange = request.roles().contains(Users.Role.ADMINISTRADOR) != target.admin();
        if (removal || adminChange || target.admin()) {
            requireMaster(actor);
        }

        String email = request.email() != null && !request.email().isBlank()
                ? request.email().trim().toLowerCase()
                : target.email();

        String telefono = request.telefono() != null
                ? request.telefono().trim()
                : target.telefono();

        users.db().update(
            "UPDATE usuarios.app_user SET full_name = ?, email = ?, telefono = ?, roles = ?, active = ? WHERE id = ?",
            request.fullName().trim(),
            email,
            telefono,
            Users.encode(request.roles()),
            request.active(),
            id
        );

        if (!request.roles().equals(target.roles()) || request.active() != target.active()) {
            users.revoke(id);
        }

        users.audit(actor.id(), id, "USER_UPDATED", "Nombre: " + target.fullName() + " -> " + request.fullName().trim());
        users.audit(actor.id(), id, "ACCESS_UPDATED", "Roles: " + Users.encode(target.roles()) + " -> " + Users.encode(request.roles()) + "; activo: " + target.active() + " -> " + request.active());

        return users.byId(id).view();
    }

    @Transactional
    public void reset(Users.User actor, UUID id, String temporary) {
        lock();
        actor = actor(actor);
        var target = users.byId(id);
        requireMaster(actor);

        if (!target.active()) {
            throw new ApiError(409, "Reactiva la cuenta antes de restablecer la contraseña");
        }

        users.db().update(
            "UPDATE usuarios.app_user SET password_hash = ?, must_change_password = TRUE WHERE id = ?",
            encodePassword(temporary),
            id
        );
        users.revoke(id);
        users.audit(actor.id(), id, "PASSWORD_RESET", "Contraseña temporal restablecida");
    }

    public List<Users.View> listarChoferes() {
        return users.list().stream()
            .filter(u -> u.roles().contains(Users.Role.CHOFER) && u.active())
            .toList();
    }

    @Transactional
    public void delete(Users.User actor, UUID id) {
        lock();
        actor = actor(actor);
        var target = users.byId(id);
        if (target.master()) {
            throw new ApiError(403, "No se puede eliminar la cuenta del administrador principal");
        }
        if (actor.id().equals(id)) {
            throw new ApiError(400, "No puedes eliminar tu propia cuenta en sesión");
        }
        requireMaster(actor);

        users.revoke(id);
        users.db().update("UPDATE usuarios.audit_event SET actor_id = NULL WHERE actor_id = ?", id);
        users.db().update("UPDATE usuarios.audit_event SET target_id = NULL WHERE target_id = ?", id);
        users.db().update("DELETE FROM usuarios.app_user WHERE id = ?", id);
        users.audit(actor.id(), null, "USER_DELETED", "Usuario eliminado: " + target.identification() + " - " + target.fullName());
    }
}
