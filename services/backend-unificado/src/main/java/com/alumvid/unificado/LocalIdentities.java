package com.alumvid.unificado;

import com.alumvid.usuarios.ApiError;
import com.alumvid.usuarios.Security;
import com.alumvid.usuarios.Users;
import java.util.UUID;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/** Uses the same stored token hash, expiration and live account state as usuarios-service. No HTTP. */
@Component
public class LocalIdentities {
    private final Users users;
    public LocalIdentities(Users users) { this.users=users; }
    public Users.User resolve(String authorization) {
        if (authorization==null || !authorization.startsWith("Bearer ")) throw new ApiError(401,"Debes iniciar sesión");
        var ids=users.db().query("SELECT user_id FROM usuarios.auth_session WHERE token_hash=? AND expires_at>CURRENT_TIMESTAMP",
            (r,n)->r.getObject(1,UUID.class), Security.hash(authorization.substring(7).trim()));
        if (ids.isEmpty()) throw new ApiError(401,"Sesión inválida o vencida");
        var user=users.byId(ids.getFirst());
        if (!user.active()) throw new ApiError(401,"Cuenta desactivada");
        return user;
    }
    public static Set<String> roles(Users.User user) { return user.roles().stream().map(Enum::name).collect(Collectors.toSet()); }
}
