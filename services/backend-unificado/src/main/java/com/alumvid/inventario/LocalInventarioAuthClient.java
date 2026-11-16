package com.alumvid.inventario;

import com.alumvid.unificado.LocalIdentities;
import com.alumvid.usuarios.ApiError;
import org.springframework.stereotype.Component;

@Component
public class LocalInventarioAuthClient extends AuthClient {
    private final LocalIdentities identities;

    public LocalInventarioAuthClient(com.alumvid.unificado.LocalIdentities identities) { super(); this.identities=identities; }
    @Override public Identity identity(String authorization) {
        try {
            var u=identities.resolve(authorization);
            return new Identity(u.id(),u.identification(),u.fullName(),LocalIdentities.roles(u),u.master(),u.active(),u.mustChangePassword());
        } catch(ApiError e) { throw new InventoryError(e.status(),e.getMessage()); }
    }

}
