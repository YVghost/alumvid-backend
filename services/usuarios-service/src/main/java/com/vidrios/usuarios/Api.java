package com.vidrios.usuarios;

import java.util.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.HttpStatus;

@RestController
@RequestMapping("/api")
class Api {
    final UserService service; final Users users;
    Api(UserService service, Users users) { this.service=service; this.users=users; }
    record Credentials(@NotBlank @Size(max=30) String identification, @NotBlank @Size(max=72) String password) {}
    record PasswordChange(@NotBlank @Size(max=72) String currentPassword,
                          @NotBlank @Size(min=12,max=72) String newPassword) {}
    record Create(@NotBlank @Pattern(regexp="[A-Za-z0-9-]{3,30}") String identification,
                  @NotBlank @Size(max=120) String fullName, @NotEmpty Set<Users.@NotNull Role> roles,
                  @NotBlank @Size(min=12,max=72) String temporaryPassword) {}
    record Update(@NotBlank @Size(max=120) String fullName, @NotEmpty Set<Users.@NotNull Role> roles, @NotNull Boolean active) {}
    record Reset(@NotBlank @Size(min=12,max=72) String temporaryPassword) {}
    @PostMapping("/auth/login") UserService.Login login(@Valid @RequestBody Credentials r) { return service.login(r.identification(),r.password()); }
    @GetMapping("/auth/me") Users.View me(@AuthenticationPrincipal Users.User u) { return u.view(); }
    @PostMapping("/auth/password") @ResponseStatus(HttpStatus.NO_CONTENT)
    void password(@AuthenticationPrincipal Users.User u, @Valid @RequestBody PasswordChange r) { service.changePassword(u,r.currentPassword(),r.newPassword()); }
    @PostMapping("/auth/logout") @ResponseStatus(HttpStatus.NO_CONTENT)
    void logout(@RequestHeader("Authorization") String authorization) { users.db.update("DELETE FROM usuarios.auth_session WHERE token_hash=?",Security.hash(authorization.substring(7))); }
    @GetMapping("/admin/users") List<Users.View> list() { return users.list(); }
    @PostMapping("/admin/users") @ResponseStatus(HttpStatus.CREATED)
    Users.View create(@AuthenticationPrincipal Users.User u,@Valid @RequestBody Create r) { return service.create(u,r); }
    @PutMapping("/admin/users/{id}") Users.View update(@AuthenticationPrincipal Users.User u,@PathVariable UUID id,@Valid @RequestBody Update r) { return service.update(u,id,r); }
    @PostMapping("/admin/users/{id}/password") @ResponseStatus(HttpStatus.NO_CONTENT)
    void reset(@AuthenticationPrincipal Users.User u,@PathVariable UUID id,@Valid @RequestBody Reset r) { service.reset(u,id,r.temporaryPassword()); }
    @GetMapping("/admin/audit") List<Map<String,Object>> audit(@AuthenticationPrincipal Users.User u) {
        if (!u.master()) throw new ApiError(403,"Solo el administrador principal puede consultar la auditoría");
        return users.db.queryForList("SELECT e.id,e.action,e.detail,e.occurred_at,a.identification AS actor,t.identification AS target FROM usuarios.audit_event e LEFT JOIN usuarios.app_user a ON a.id=e.actor_id LEFT JOIN usuarios.app_user t ON t.id=e.target_id ORDER BY e.occurred_at DESC LIMIT 200");
    }
}
