package com.alumvid.logistica.security;

import com.alumvid.unificado.LocalIdentities;
import com.alumvid.usuarios.ApiError;
import org.springframework.stereotype.Component;

@Component
public class LocalLogisticaAuthClient extends AuthClient {
    private final LocalIdentities identities;
    private final com.alumvid.usuarios.UserService userService; private final com.fasterxml.jackson.databind.ObjectMapper json;
    public LocalLogisticaAuthClient(com.alumvid.unificado.LocalIdentities identities, com.alumvid.usuarios.UserService userService, com.fasterxml.jackson.databind.ObjectMapper json) { super(); this.identities=identities;this.userService=userService;this.json=json; }
    @Override public Identity identity(String authorization) {
        try {
            var u=identities.resolve(authorization);
            return new Identity(u.id(),u.identification(),u.fullName(),LocalIdentities.roles(u),u.master(),u.active(),u.mustChangePassword());
        } catch(ApiError e) { throw new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatusCode.valueOf(e.status()),e.getMessage()); }
    }

    @Override public java.util.List<java.util.Map<String,Object>> activeDrivers(String authorization) {
        var actor=identities.resolve(authorization);
        if(actor.mustChangePassword()) throw new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.FORBIDDEN,"Debes cambiar la clave temporal");
        return userService.listarChoferes().stream().map(u -> json.convertValue(u,new com.fasterxml.jackson.core.type.TypeReference<java.util.Map<String,Object>>() {})).toList();
    }

}
