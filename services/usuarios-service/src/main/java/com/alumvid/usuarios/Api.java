package com.alumvid.usuarios;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping({"/api", "/api/v1"})
public class Api {

    private final UserService service;
    private final Users users;

    public Api(UserService service, Users users) {
        this.service = service;
        this.users = users;
    }

    public record Credentials(
        String identification,
        String email,
        @NotBlank @Size(max = 72) String password
    ) {
        public String identifier() {
            if (identification != null && !identification.isBlank()) return identification;
            if (email != null && !email.isBlank()) return email;
            throw new ApiError(400, "Debes proporcionar identificación o correo electrónico");
        }
    }

    public record PasswordChange(
        @NotBlank @Size(max = 72) String currentPassword,
        @NotBlank @Size(min = 12, max = 72) String newPassword
    ) {}

    public record Create(
        @NotBlank @Pattern(regexp = "[A-Za-z0-9-]{3,30}") String identification,
        String email,
        String telefono,
        @NotBlank @Size(max = 120) String fullName,
        @NotEmpty Set<Users.@NotNull Role> roles,
        @NotBlank @Size(min = 12, max = 72) String temporaryPassword
    ) {}

    public record Update(
        @NotBlank @Size(max = 120) String fullName,
        String email,
        String telefono,
        @NotEmpty Set<Users.@NotNull Role> roles,
        @NotNull Boolean active
    ) {}

    public record Reset(
        @NotBlank @Size(min = 12, max = 72) String temporaryPassword
    ) {}

    @PostMapping("/auth/login")
    public UserService.Login login(@Valid @RequestBody Credentials r) {
        return service.login(r.identifier(), r.password());
    }

    @GetMapping("/auth/me")
    public Users.View me(@AuthenticationPrincipal Users.User u) {
        if (u == null) throw new ApiError(401, "No autenticado");
        return u.view();
    }

    @PostMapping("/auth/password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void password(@AuthenticationPrincipal Users.User u, @Valid @RequestBody PasswordChange r) {
        if (u == null) throw new ApiError(401, "No autenticado");
        service.changePassword(u, r.currentPassword(), r.newPassword());
    }

    @PostMapping("/auth/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@RequestHeader(value = "Authorization", required = false) String authorization) {
        if (authorization != null && authorization.startsWith("Bearer ")) {
            String token = authorization.substring(7).trim();
            users.db().update("DELETE FROM usuarios.auth_session WHERE token_hash = ?", Security.hash(token));
        }
    }

    @GetMapping("/admin/users")
    public List<Users.View> listUsers(@AuthenticationPrincipal Users.User u) {
        if (u == null || !u.admin()) throw new ApiError(403, "Se requieren permisos administrativos");
        return users.list();
    }

    @PostMapping("/admin/users")
    @ResponseStatus(HttpStatus.CREATED)
    public Users.View createUser(@AuthenticationPrincipal Users.User u, @Valid @RequestBody Create r) {
        if (u == null) throw new ApiError(401, "No autenticado");
        return service.create(u, r);
    }

    @PutMapping("/admin/users/{id}")
    public Users.View updateUser(@AuthenticationPrincipal Users.User u, @PathVariable UUID id, @Valid @RequestBody Update r) {
        if (u == null) throw new ApiError(401, "No autenticado");
        return service.update(u, id, r);
    }

    @PostMapping("/admin/users/{id}/password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void resetPassword(@AuthenticationPrincipal Users.User u, @PathVariable UUID id, @Valid @RequestBody Reset r) {
        if (u == null) throw new ApiError(401, "No autenticado");
        service.reset(u, id, r.temporaryPassword());
    }

    @DeleteMapping("/admin/users/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteUser(@AuthenticationPrincipal Users.User u, @PathVariable UUID id) {
        if (u == null) throw new ApiError(401, "No autenticado");
        service.delete(u, id);
    }

    @GetMapping("/admin/audit")
    public List<Map<String, Object>> audit(@AuthenticationPrincipal Users.User u) {
        if (u == null) throw new ApiError(401, "No autenticado");
        if (!u.master()) throw new ApiError(403, "Solo el administrador principal puede consultar la auditoría");
        return users.db().queryForList(
            "SELECT e.id, e.action, e.detail, e.occurred_at, a.identification AS actor, t.identification AS target " +
            "FROM usuarios.audit_event e " +
            "LEFT JOIN usuarios.app_user a ON a.id = e.actor_id " +
            "LEFT JOIN usuarios.app_user t ON t.id = e.target_id " +
            "ORDER BY e.occurred_at DESC LIMIT 200"
        );
    }

    @GetMapping("/choferes")
    public List<Users.View> listDrivers() {
        return service.listarChoferes();
    }
}
