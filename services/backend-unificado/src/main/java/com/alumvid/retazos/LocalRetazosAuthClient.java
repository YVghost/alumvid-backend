package com.alumvid.retazos;

import com.alumvid.unificado.LocalIdentities;
import com.alumvid.usuarios.ApiError;
import org.springframework.stereotype.Component;

@Component
public class LocalRetazosAuthClient extends AuthClient {
    private final LocalIdentities identities;

    public LocalRetazosAuthClient(com.alumvid.unificado.LocalIdentities identities) { super(); this.identities=identities; }
    @Override public Identity identity(String authorization) {
        try {
            var u=identities.resolve(authorization);
            return new Identity(u.id(),u.identification(),u.fullName(),LocalIdentities.roles(u),u.master(),u.active(),u.mustChangePassword());
        } catch(ApiError e) { throw new RetazosError(e.status(),e.getMessage()); }
    }

}
