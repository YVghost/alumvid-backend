package com.alumvid.logistica.security;

import com.alumvid.logistica.controller.LogisticaController;
import com.alumvid.logistica.dto.RutaResponse;
import com.alumvid.logistica.service.LogisticaService;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(LogisticaController.class) @Import(LogisticaSecurity.class)
class PlanningSecurityTest {
    @Autowired MockMvc mvc;
    @MockitoBean AuthClient auth;
    @MockitoBean LogisticaService service;
    @MockitoBean SimpMessagingTemplate messages;
    static final UUID DRIVER=UUID.randomUUID(),OTHER=UUID.randomUUID();
    @BeforeEach void identities() {
        for(String role:List.of("ADMINISTRADOR","BODEGUERO","CHOFER","VENDEDOR")) {
            when(auth.identity("Bearer "+role)).thenReturn(new AuthClient.Identity(DRIVER,"TEST","Usuario",Set.of(role),false,true,false));
        }
        when(service.crearRuta(any())).thenReturn(new RutaResponse());
        when(service.listarRutas()).thenReturn(List.of());when(service.listarRutasPorChofer(any())).thenReturn(List.of());
    }
    void create(String role,UUID driver,int expected) throws Exception {
        mvc.perform(post("/api/v1/logistica/rutas").header("Authorization","Bearer "+role).contentType("application/json").content("{\"choferId\":\""+driver+"\"}")).andExpect(status().is(expected));
    }
    @Test void adminAndWarehouseCreateRoutesForAvailableDrivers() throws Exception {create("ADMINISTRADOR",OTHER,201);create("BODEGUERO",OTHER,201);}
    @Test void driverCreatesOwnRouteButNeverAnotherDrivers() throws Exception {create("CHOFER",DRIVER,201);create("CHOFER",OTHER,403);}
    @Test void sellerCannotCreateRoutes() throws Exception {create("VENDEDOR",DRIVER,403);}
    @Test void driverRouteListIsScopedToTheirOwnId() throws Exception {
        mvc.perform(get("/api/v1/logistica/rutas").header("Authorization","Bearer CHOFER")).andExpect(status().isOk());
        verify(service).listarRutasPorChofer(DRIVER);verify(service,never()).listarRutas();
    }
    @Test void newPlanningRolesDoNotGainAdministrativeRouteEdits() throws Exception {
        for(String role:List.of("BODEGUERO","CHOFER"))mvc.perform(delete("/api/v1/logistica/rutas/"+OTHER).header("Authorization","Bearer "+role)).andExpect(status().isForbidden());
    }
}
