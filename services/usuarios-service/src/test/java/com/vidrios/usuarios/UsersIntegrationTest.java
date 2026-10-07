package com.vidrios.usuarios;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.env.Environment;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import static org.junit.jupiter.api.Assertions.*;

/** Ejecutar contra la base local recién inicializada. Cada prueba revierte sus cambios. */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class UsersIntegrationTest {
    @Autowired MockMvc mvc;
    @Autowired Users users;
    @Autowired UserService service;
    @Autowired Environment env;
    Users.User master;
    String masterToken;
    static final String TEMP="Temporal-2026-segura";
    static final String FINAL="Definitiva-2026-segura";
    @BeforeEach void ready() {
        master=users.byIdentification(env.getProperty("app.master.identification")).orElseThrow();
        // La clave usada en las pruebas se revierte al terminar cada transacción.
        service.changePassword(master,env.getProperty("app.master.password"),FINAL);
        master=users.byId(master.id());
        masterToken=service.login(master.identification(),FINAL).accessToken();
    }
    Users.User employee(Set<Users.Role> roles) {
        return users.byId(service.create(master,new Api.Create("TEST-"+UUID.randomUUID().toString().substring(0,8),"Empleado de prueba",roles,TEMP)).id());
    }
    String permanentToken(Users.User u) {
        service.changePassword(u,TEMP,FINAL);
        return service.login(u.identification(),FINAL).accessToken();
    }
    @Test void requiresAuthenticationAndAdminRole() throws Exception {
        mvc.perform(get("/api/admin/users")).andExpect(status().isUnauthorized());
        var u=employee(Set.of(Users.Role.VENDEDOR));
        mvc.perform(get("/api/admin/users").header("Authorization","Bearer "+permanentToken(u))).andExpect(status().isForbidden());
    }
    @Test void temporaryPasswordBlocksBusinessAccessAndChangeRevokesSession() throws Exception {
        var u=employee(Set.of(Users.Role.ADMINISTRADOR));
        String token=service.login(u.identification(),TEMP).accessToken();
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+token)).andExpect(status().isOk()).andExpect(jsonPath("$.mustChangePassword").value(true));
        mvc.perform(get("/api/admin/users").header("Authorization","Bearer "+token)).andExpect(status().isForbidden());
        mvc.perform(post("/api/auth/password").header("Authorization","Bearer "+token).contentType("application/json")
            .content("{\"currentPassword\":\""+TEMP+"\",\"newPassword\":\""+FINAL+"\"}")).andExpect(status().isNoContent());
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+token)).andExpect(status().isUnauthorized());
        assertFalse(users.byId(u.id()).mustChangePassword());
    }
    @Test void delegateCanAddOperationalRolesButCannotRemoveOrPromote() throws Exception {
        var delegate=employee(Set.of(Users.Role.ADMINISTRADOR));
        String token=permanentToken(delegate);
        var target=employee(Set.of(Users.Role.VENDEDOR));
        mvc.perform(put("/api/admin/users/"+target.id()).header("Authorization","Bearer "+token).contentType("application/json")
            .content("{\"fullName\":\"Empleado\",\"roles\":[\"VENDEDOR\",\"BODEGUERO\"],\"active\":true}"))
            .andExpect(status().isOk());
        mvc.perform(put("/api/admin/users/"+target.id()).header("Authorization","Bearer "+token).contentType("application/json")
            .content("{\"fullName\":\"Empleado\",\"roles\":[\"VENDEDOR\"],\"active\":true}"))
            .andExpect(status().isForbidden());
        mvc.perform(put("/api/admin/users/"+target.id()).header("Authorization","Bearer "+token).contentType("application/json")
            .content("{\"fullName\":\"Empleado\",\"roles\":[\"VENDEDOR\",\"BODEGUERO\",\"ADMINISTRADOR\"],\"active\":true}"))
            .andExpect(status().isForbidden());
        mvc.perform(post("/api/admin/users/"+master.id()+"/password").header("Authorization","Bearer "+token).contentType("application/json")
            .content("{\"temporaryPassword\":\""+TEMP+"\"}")).andExpect(status().isForbidden());
    }
    @Test void deactivationPreservesUserAndAuditAndRevokesSession() throws Exception {
        var u=employee(Set.of(Users.Role.CHOFER)); String token=permanentToken(u);
        service.update(master,u.id(),new Api.Update(u.fullName(),u.roles(),false));
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+token)).andExpect(status().isUnauthorized());
        assertFalse(users.byId(u.id()).active());
        assertTrue(users.db().queryForObject("SELECT count(*) FROM usuarios.audit_event WHERE target_id=?",Integer.class,u.id())>=3);
        assertThrows(ApiError.class,()->service.login(u.identification(),FINAL));
    }
    @Test void principalCannotBeDeactivatedOrLoseAdministratorRole() {
        assertEquals(409,assertThrows(ApiError.class,()->service.update(master,master.id(),new Api.Update(master.fullName(),master.roles(),false))).status);
        assertEquals(409,assertThrows(ApiError.class,()->service.update(master,master.id(),new Api.Update(master.fullName(),Set.of(Users.Role.CHOFER),true))).status);
    }
    @Test void resetAndRoleChangesInvalidateExistingSessions() throws Exception {
        var u=employee(Set.of(Users.Role.VENDEDOR));String token=permanentToken(u);
        service.update(master,u.id(),new Api.Update(u.fullName(),Set.of(Users.Role.VENDEDOR,Users.Role.BODEGUERO),true));
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+token)).andExpect(status().isUnauthorized());
        String newToken=service.login(u.identification(),FINAL).accessToken();
        service.reset(master,u.id(),TEMP);
        mvc.perform(get("/api/auth/me").header("Authorization","Bearer "+newToken)).andExpect(status().isUnauthorized());
        assertTrue(service.login(u.identification(),TEMP).user().mustChangePassword());
    }
    @Test void validatesInputAndRejectsDuplicateIdentification() throws Exception {
        mvc.perform(post("/api/admin/users").header("Authorization","Bearer "+masterToken).contentType("application/json")
            .content("{\"identification\":\"123\",\"fullName\":\"Usuario\",\"roles\":[],\"temporaryPassword\":\"corta\"}"))
            .andExpect(status().isBadRequest());
        mvc.perform(post("/api/admin/users").header("Authorization","Bearer "+masterToken).contentType("application/json")
            .content("{\"identification\":\""+master.identification()+"\",\"fullName\":\"Usuario\",\"roles\":[\"VENDEDOR\"],\"temporaryPassword\":\""+TEMP+"\"}"))
            .andExpect(status().isConflict());
    }
}
