package com.vidrios.inventario_service;

import java.math.BigDecimal;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class InventoryIntegrationTest {
    @Autowired InventoryRepository products;
    @Autowired InventoryService service;
    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate db;
    @MockitoBean AuthClient auth;
    final AuthClient.Identity admin=identity("ADMINISTRADOR");
    final AuthClient.Identity warehouse=identity("BODEGUERO");
    final AuthClient.Identity seller=identity("VENDEDOR");
    static AuthClient.Identity identity(String role) { return new AuthClient.Identity(UUID.randomUUID(),"TEST-ID","Operador de prueba",Set.of(role),false,true,false); }
    @BeforeEach void auth() {
        when(auth.identity("Bearer admin")).thenReturn(admin);
        when(auth.identity("Bearer warehouse")).thenReturn(warehouse);
        when(auth.identity("Bearer seller")).thenReturn(seller);
    }
    InventoryApi.ProductInput input(String code,InventoryRepository.Unit unit,boolean active) {
        return new InventoryApi.ProductInput(code,"Producto de prueba","VIDRIO",unit,"Descripción","Proveedor","EXT-1","BM",new BigDecimal("2"),active);
    }
    InventoryRepository.Product product() { return service.create(input("TST-"+UUID.randomUUID(),InventoryRepository.Unit.UNIDAD,true),admin); }
    InventoryApi.MovementInput move(InventoryRepository.MovementType type,String quantity) {
        return new InventoryApi.MovementInput(UUID.randomUUID(),type,new BigDecimal(quantity),"Motivo de prueba","REF-1");
    }
    @Test void rolesRestrictWritesButAllowConsultation() throws Exception {
        var p=product();
        mvc.perform(get("/api/products")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/products").header("Authorization","Bearer seller")).andExpect(status().isOk());
        mvc.perform(get("/api/products/"+p.id()).header("Authorization","Bearer seller")).andExpect(jsonPath("$.stock").value("0.0000"));
        mvc.perform(post("/api/products").header("Authorization","Bearer warehouse").contentType("application/json").content("{}"))
            .andExpect(status().isForbidden());
        String body="{\"requestId\":\""+UUID.randomUUID()+"\",\"type\":\"INGRESO\",\"quantity\":5,\"reason\":\"Recepción\"}";
        mvc.perform(post("/api/products/"+p.id()+"/movements").header("Authorization","Bearer seller").contentType("application/json").content(body)).andExpect(status().isForbidden());
        mvc.perform(post("/api/products/"+p.id()+"/movements").header("Authorization","Bearer warehouse").contentType("application/json").content(body)).andExpect(status().isOk());
        mvc.perform(post("/api/products/"+p.id()+"/movements").header("Authorization","Bearer warehouse").contentType("application/json").content(body.replace("INGRESO","AJUSTE"))).andExpect(status().isForbidden());
    }
    @Test void preservesDecimalStockAndLedger() {
        var p=product();
        service.move(p.id(),move(InventoryRepository.MovementType.INGRESO,"62.83"),warehouse);
        var out=service.move(p.id(),move(InventoryRepository.MovementType.SALIDA,"0.33"),warehouse);
        assertEquals(0,new BigDecimal("62.50").compareTo(products.get(p.id(),false).stock()));
        assertEquals(0,new BigDecimal("62.83").compareTo(out.stockBefore()));
        assertEquals(warehouse.id(),out.actorId());assertEquals("Motivo de prueba",out.reason());
        assertEquals(2,products.movements(p.id(),0,20).total());
    }
    @Test void duplicateRequestsDoNotDoubleStockAndChangedPayloadIsRejected() {
        var p=product();var request=move(InventoryRepository.MovementType.INGRESO,"10");
        var first=service.move(p.id(),request,admin);var second=service.move(p.id(),request,admin);
        assertEquals(first.id(),second.id());assertEquals(1,products.movements(p.id(),0,20).total());
        var changed=new InventoryApi.MovementInput(request.requestId(),request.type(),new BigDecimal("11"),request.reason(),request.reference());
        assertEquals(409,assertThrows(InventoryError.class,()->service.move(p.id(),changed,admin)).status);
    }
    @Test void insufficientStockDoesNotCreateMovement() {
        var p=product();service.move(p.id(),move(InventoryRepository.MovementType.INGRESO,"3"),admin);
        assertEquals(409,assertThrows(InventoryError.class,()->service.move(p.id(),move(InventoryRepository.MovementType.SALIDA,"4"),warehouse)).status);
        assertEquals(0,new BigDecimal("3").compareTo(products.get(p.id(),false).stock()));
        assertEquals(1,products.movements(p.id(),0,20).total());
    }
    @Test void adjustmentUsesPhysicalTotalAndDeactivationPreservesHistory() {
        var p=product();service.move(p.id(),move(InventoryRepository.MovementType.INGRESO,"10"),admin);
        var adjust=service.move(p.id(),move(InventoryRepository.MovementType.AJUSTE,"4"),admin);
        assertEquals(0,new BigDecimal("-6").compareTo(adjust.delta()));
        assertEquals(409,assertThrows(InventoryError.class,()->service.update(p.id(),input(p.code(),p.unit(),false),admin)).status);
        service.move(p.id(),move(InventoryRepository.MovementType.AJUSTE,"0"),admin);
        service.update(p.id(),input(p.code(),p.unit(),false),admin);
        assertFalse(products.get(p.id(),false).active());assertEquals(3,products.movements(p.id(),0,20).total());
        assertTrue(products.history(p.id()).size()>=2);
        assertThrows(InventoryError.class,()->service.move(p.id(),move(InventoryRepository.MovementType.INGRESO,"1"),admin));
    }
    @Test void cannotChangeUnitAfterMovementAndValidatesScaleAndReason() throws Exception {
        var p=product();service.move(p.id(),move(InventoryRepository.MovementType.INGRESO,"1"),admin);
        assertEquals(409,assertThrows(InventoryError.class,()->service.update(p.id(),input(p.code(),InventoryRepository.Unit.METRO,true),admin)).status);
        mvc.perform(post("/api/products/"+p.id()+"/movements").header("Authorization","Bearer admin").contentType("application/json")
            .content("{\"requestId\":\""+UUID.randomUUID()+"\",\"type\":\"INGRESO\",\"quantity\":0.00001,\"reason\":\" \"}"))
            .andExpect(status().isBadRequest());
        mvc.perform(get("/api/products?size=101").header("Authorization","Bearer admin")).andExpect(status().isBadRequest());
    }
    @Test void authOutageReturns503AndHealthRemainsAvailable() throws Exception {
        when(auth.identity("Bearer unavailable")).thenThrow(new InventoryError(503,"El servicio de usuarios no está disponible"));
        mvc.perform(get("/api/products").header("Authorization","Bearer unavailable")).andExpect(status().isServiceUnavailable());
        mvc.perform(get("/actuator/health")).andExpect(status().isOk());
        var realClient=new AuthClient("http://127.0.0.1:1");
        assertEquals(503,assertThrows(InventoryError.class,()->realClient.identity("Bearer test")).status);
    }
    @Test @Transactional(propagation=Propagation.NOT_SUPPORTED)
    void simultaneousWithdrawalsCannotOversell() throws Exception {
        var p=product();var executor=Executors.newFixedThreadPool(2);var start=new CountDownLatch(1);
        try {
            service.move(p.id(),move(InventoryRepository.MovementType.INGRESO,"10"),admin);
            Callable<Boolean> withdrawal=()->{start.await();try{service.move(p.id(),move(InventoryRepository.MovementType.SALIDA,"7"),warehouse);return true;}catch(InventoryError e){assertEquals(409,e.status);return false;}};
            var a=executor.submit(withdrawal);var b=executor.submit(withdrawal);start.countDown();
            assertNotEquals(a.get(10,TimeUnit.SECONDS),b.get(10,TimeUnit.SECONDS));
            assertEquals(0,new BigDecimal("3").compareTo(products.get(p.id(),false).stock()));
            assertEquals(2,products.movements(p.id(),0,20).total());
        } finally {
            executor.shutdownNow();executor.awaitTermination(5,TimeUnit.SECONDS);
            db.update("DELETE FROM inventario.movement WHERE product_id=?",p.id());
            db.update("DELETE FROM inventario.catalog_event WHERE product_id=?",p.id());
            db.update("DELETE FROM inventario.product WHERE id=?",p.id());
        }
    }
}
