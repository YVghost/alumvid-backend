package com.alumvid.retazos;

import java.math.BigDecimal;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.*;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.*;
import org.testcontainers.containers.PostgreSQLContainer;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@Import(RetazosIntegrationTest.AuthTest.class)
@Transactional
class RetazosIntegrationTest {
    static final PostgreSQLContainer<?> PG=new PostgreSQLContainer<>("postgres:16-alpine");
    static final AuthClient.Identity ADMIN=identity("ADMINISTRADOR",false);
    static final AuthClient.Identity WAREHOUSE=identity("BODEGUERO",false);
    static AuthClient.Identity identity(String role,boolean temporary) { return new AuthClient.Identity(UUID.randomUUID(),"TEST-01","Operador de prueba",Set.of(role),false,true,temporary); }
    @TestConfiguration static class AuthTest {
        @Bean @Primary AuthClient testAuth() {
            return new AuthClient("http://127.0.0.1:1") {
                @Override Identity identity(String value) {
                    return switch(value) {
                        case "Bearer admin"->ADMIN;
                        case "Bearer warehouse"->WAREHOUSE;
                        case "Bearer seller"->RetazosIntegrationTest.identity("VENDEDOR",false);
                        case "Bearer driver"->RetazosIntegrationTest.identity("CHOFER",false);
                        case "Bearer temporary"->RetazosIntegrationTest.identity("ADMINISTRADOR",true);
                        default->throw new RetazosError(401,"Token inválido");
                    };
                }
            };
        }
    }
    @DynamicPropertySource static void database(DynamicPropertyRegistry registry) {
        PG.start();
        String migrations=Path.of("../inventario-service/src/main/resources/db/migration").toAbsolutePath().normalize().toString().replace('\\','/');
        Flyway.configure().dataSource(PG.getJdbcUrl(),PG.getUsername(),PG.getPassword()).schemas("inventario").defaultSchema("inventario").locations("filesystem:"+migrations).load().migrate();
        registry.add("spring.datasource.url",PG::getJdbcUrl);
        registry.add("spring.datasource.username",PG::getUsername);
        registry.add("spring.datasource.password",PG::getPassword);
    }
    @Autowired RetazosService service;
    @Autowired RetazosRepository repository;
    @Autowired MockMvc mvc;
    static BigDecimal d(String value) { return new BigDecimal(value); }
    void eq(String expected,Object actual) { assertEquals(0,d(expected).compareTo(new BigDecimal(actual.toString()))); }
    UUID product(String stock) {
        UUID id=UUID.randomUUID();
        repository.db().update("INSERT INTO inventario.product(id,code,name,category,unit,min_stock,stock) VALUES (?,?,?,'ALUMINIO','UNIDAD',0,?)",id,"TST-"+id,"Producto de prueba",d(stock));
        return id;
    }
    UUID aluminum(String stock) {
        UUID id=product(stock);service.configure(id,new RetazosApi.FormatInput(RetazosApi.Kind.ALUMINIO,d("6.4"),null,null),ADMIN);return id;
    }
    UUID glass() {
        UUID id=product("0");service.configure(id,new RetazosApi.FormatInput(RetazosApi.Kind.VIDRIO,null,d("183"),d("244")),ADMIN);return id;
    }
    RetazosApi.RegisterInput profile(String length,int count,RetazosApi.EntryMode mode,UUID request) {
        return new RetazosApi.RegisterInput(request,mode,count,d(length),null,null,"Percha A","Ingreso verificado");
    }
    Map<String,Object> profile(UUID id,String length,int count) { return service.register(id,profile(length,count,RetazosApi.EntryMode.NUEVO,UUID.randomUUID()),ADMIN); }
    UUID first(Map<String,Object> operation) { return UUID.fromString(((List<?>)operation.get("pieceIds")).getFirst().toString()); }
    RetazosApi.CutInput cut(String used,String waste,UUID request) { return new RetazosApi.CutInput(request,d(used),null,d(waste),null,"Corte para pedido"); }
    long movements(UUID id) { return repository.db().queryForObject("SELECT count(*) FROM inventario.movement WHERE product_id=?",Long.class,id); }
    @Test void fullProfileAndHalfProfileTotalOneAndHalf() {
        UUID id=aluminum("0");profile(id,"6.4",1);profile(id,"3.2",1);
        var summary=service.summary(id);eq("1.5",summary.get("calculatedStock"));
        assertEquals(1L,summary.get("fullPieces"));assertEquals(1L,summary.get("remnantPieces"));eq("0",summary.get("unallocatedUnits"));
    }
    @Test void twoHalfProfilesRemainTwoPhysicalRemnants() {
        UUID id=aluminum("0");profile(id,"3.2",2);
        var summary=service.summary(id);eq("1",summary.get("calculatedStock"));
        assertEquals(0L,summary.get("fullPieces"));assertEquals(2L,summary.get("remnantPieces"));
        var groups=(List<?>)summary.get("breakdown");assertEquals(1,groups.size());
        var group=(Map<?,?>)groups.getFirst();eq("50",group.get("percentagePerPiece"));assertEquals(2L,group.get("quantity"));
    }
    @Test void existingStockIsDetailedWithoutAddingItAgain() {
        UUID id=aluminum("1.5");
        service.register(id,profile("6.4",1,RetazosApi.EntryMode.EXISTENTE,UUID.randomUUID()),ADMIN);
        service.register(id,profile("3.2",1,RetazosApi.EntryMode.EXISTENTE,UUID.randomUUID()),ADMIN);
        eq("1.5",repository.product(id,false).get("stock"));eq("0",service.summary(id).get("unallocatedUnits"));assertEquals(0,movements(id));
        assertEquals(409,assertThrows(RetazosError.class,()->service.register(id,profile("0.1",1,RetazosApi.EntryMode.EXISTENTE,UUID.randomUUID()),ADMIN)).status);
    }
    @Test void glassCutKeepsHeightAndUsesAreaEquivalence() {
        UUID id=glass();
        var registered=service.register(id,new RetazosApi.RegisterInput(UUID.randomUUID(),RetazosApi.EntryMode.NUEVO,1,null,d("183"),d("244"),"Vidrios","Ingreso de plancha"),ADMIN);
        UUID origin=first(registered);
        var result=service.cut(id,origin,new RetazosApi.CutInput(UUID.randomUUID(),null,d("3"),null,d("0"),"Corte de franja de 3 cm"),WAREHOUSE);
        var rest=repository.piece(id,first(result));eq("180",rest.widthCm());eq("244",rest.heightCm());eq("43920",rest.measure());
        eq("0.983606557377",result.get("stockAfter"));assertEquals("TRANSFORMADO",repository.piece(id,origin).state());
        assertEquals(origin,rest.parentId());
    }
    @Test void glassCannotChangeHeightOrExceedReference() {
        UUID id=glass();
        assertEquals(400,assertThrows(RetazosError.class,()->service.register(id,new RetazosApi.RegisterInput(UUID.randomUUID(),RetazosApi.EntryMode.NUEVO,1,null,d("180"),d("240"),"","No permitido"),ADMIN)).status);
        assertEquals(400,assertThrows(RetazosError.class,()->profile(id,"3.2",1)).status);
    }
    @Test void cuttingIncludesWasteAndDoesNotDoubleCountOriginal() {
        UUID id=aluminum("0");UUID origin=first(profile(id,"6.4",1));
        var result=service.cut(id,origin,cut("3.2","0.1",UUID.randomUUID()),WAREHOUSE);
        eq("3.1",repository.piece(id,first(result)).lengthM());eq("0.484375",result.get("stockAfter"));
        assertEquals(1L,service.summary(id).get("availablePieces"));assertEquals(2,movements(id));
    }
    @Test void suitableRemnantsMustBeUsedBeforeWholeMaterial() {
        UUID id=aluminum("0");UUID full=first(profile(id,"6.4",1));UUID remnant=first(profile(id,"3.2",1));
        assertEquals(409,assertThrows(RetazosError.class,()->service.cut(id,full,cut("1","0",UUID.randomUUID()),WAREHOUSE)).status);
        var result=service.cut(id,remnant,cut("1","0",UUID.randomUUID()),WAREHOUSE);eq("1.34375",result.get("stockAfter"));
    }
    @Test void retriesAreIdempotentAndChangedRequestIsRejected() {
        UUID id=aluminum("0");UUID request=UUID.randomUUID();var input=profile("6.4",1,RetazosApi.EntryMode.NUEVO,request);
        var first=service.register(id,input,ADMIN);var again=service.register(id,input,ADMIN);
        assertEquals(first.get("id").toString(),again.get("id").toString());assertEquals(1,movements(id));
        assertEquals(409,assertThrows(RetazosError.class,()->service.register(id,profile("3.2",1,RetazosApi.EntryMode.NUEVO,request),ADMIN)).status);
        UUID cutRequest=UUID.randomUUID();var cut=cut("3.2","0",cutRequest);
        var cutResult=service.cut(id,first(first),cut,WAREHOUSE);service.cut(id,first(first),cut,WAREHOUSE);
        eq("0.5",cutResult.get("stockAfter"));assertEquals(2,movements(id));
    }
    @Test void repeatedCutsUsePhysicalMeasureBeforeRoundingTotals() {
        UUID id=aluminum("0");UUID current=first(profile(id,"6.4",1));
        for(int i=0;i<10;i++)current=first(service.cut(id,current,cut("0.1","0",UUID.randomUUID()),WAREHOUSE));
        eq("5.4",repository.piece(id,current).lengthM());eq("0.84375",repository.product(id,false).get("stock"));
    }
    @Test void discardKeepsHistoryAndReconciliationOnlyChangesUnallocatedBalance() {
        UUID id=aluminum("1.5");var operation=service.register(id,profile("3.2",1,RetazosApi.EntryMode.EXISTENTE,UUID.randomUUID()),ADMIN);
        var reconcile=service.reconcile(id,new RetazosApi.ReconcileInput(UUID.randomUUID(),d("0"),"Conteo físico terminado"),ADMIN);
        eq("0.5",reconcile.get("stockAfter"));UUID piece=first(operation);
        var request=new RetazosApi.ReasonInput(UUID.randomUUID(),"Pieza dañada");service.discard(id,piece,request,WAREHOUSE);service.discard(id,piece,request,WAREHOUSE);
        eq("0",repository.product(id,false).get("stock"));assertEquals("DESCARTADO",repository.piece(id,piece).state());assertEquals(2,movements(id));
    }
    @Test void permissionsTemporaryPasswordAndInvalidMeasurementsAreEnforced() throws Exception {
        UUID id=product("0");
        mvc.perform(get("/api/retazos/products")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/retazos/products").header("Authorization","Bearer seller")).andExpect(status().isOk());
        mvc.perform(get("/api/retazos/products").header("Authorization","Bearer driver")).andExpect(status().isForbidden());
        mvc.perform(get("/api/retazos/products").header("Authorization","Bearer temporary")).andExpect(status().isForbidden());
        mvc.perform(put("/api/retazos/products/"+id+"/format").header("Authorization","Bearer warehouse").contentType("application/json").content("{\"kind\":\"ALUMINIO\",\"fullLengthM\":6.4}")).andExpect(status().isForbidden());
        mvc.perform(put("/api/retazos/products/"+id+"/format").header("Authorization","Bearer admin").contentType("application/json").content("{\"kind\":\"ALUMINIO\",\"fullLengthM\":0}")).andExpect(status().isBadRequest());
    }
    @Test @Transactional(propagation=Propagation.NOT_SUPPORTED)
    void databaseRejectsPiecesWithoutDimensions() {
        UUID id=aluminum("0");
        try {
            assertThrows(org.springframework.dao.DataIntegrityViolationException.class,()->repository.db().update("INSERT INTO retazos.piece(id,product_id,location) VALUES (?,?,'Sin medidas')",UUID.randomUUID(),id));
            assertEquals(0L,service.summary(id).get("availablePieces"));
        } finally { cleanup(id); }
    }
    @Test @Transactional(propagation=Propagation.NOT_SUPPORTED)
    void inventoryMigrationPreservesExistingQuantities() throws Exception {
        String database="migration_"+UUID.randomUUID().toString().replace("-","");
        repository.db().execute("CREATE DATABASE "+database);
        String url=PG.getJdbcUrl().replace("/"+PG.getDatabaseName(),"/"+database);
        String migrations=Path.of("../inventario-service/src/main/resources/db/migration").toAbsolutePath().normalize().toString().replace('\\','/');
        Flyway.configure().dataSource(url,PG.getUsername(),PG.getPassword()).schemas("inventario").defaultSchema("inventario").locations("filesystem:"+migrations).target("1").load().migrate();
        var probe=new org.springframework.jdbc.core.JdbcTemplate(new org.springframework.jdbc.datasource.DriverManagerDataSource(url,PG.getUsername(),PG.getPassword()));
        UUID id=UUID.randomUUID();
        probe.update("INSERT INTO inventario.product(id,code,name,category,unit,min_stock,stock) VALUES (?,'MIGRATION','Existente','VIDRIO','UNIDAD',0,62.83)",id);
        Flyway.configure().dataSource(url,PG.getUsername(),PG.getPassword()).schemas("inventario").defaultSchema("inventario").locations("filesystem:"+migrations).load().migrate();
        eq("62.83",probe.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,id));
        assertEquals(false,probe.queryForObject("SELECT pieces_managed FROM inventario.product WHERE id=?",Boolean.class,id));
    }
    @Test @Transactional(propagation=Propagation.NOT_SUPPORTED)
    void simultaneousCutsOfSamePieceOnlyConsumeItOnce() throws Exception {
        UUID id=aluminum("0");var executor=Executors.newFixedThreadPool(2);var start=new CountDownLatch(1);
        try {
            UUID piece=first(profile(id,"6.4",1));
            Callable<Boolean> worker=()->{start.await();try{service.cut(id,piece,cut("3.2","0",UUID.randomUUID()),WAREHOUSE);return true;}catch(RetazosError e){assertEquals(409,e.status);return false;}};
            var a=executor.submit(worker);var b=executor.submit(worker);start.countDown();assertNotEquals(a.get(10,TimeUnit.SECONDS),b.get(10,TimeUnit.SECONDS));
            eq("0.5",repository.product(id,false).get("stock"));assertEquals(1L,service.summary(id).get("availablePieces"));assertEquals(2,movements(id));
        } finally { executor.shutdownNow();executor.awaitTermination(5,TimeUnit.SECONDS);cleanup(id); }
    }
    @Test @Transactional(propagation=Propagation.NOT_SUPPORTED)
    void failureInOperationHistoryRollsBackPieceAndInventoryMovement() {
        UUID id=aluminum("0");
        repository.db().execute("ALTER TABLE retazos.operation ADD CONSTRAINT test_rollback CHECK (reason<>'FORCE_ROLLBACK')");
        try {
            var request=new RetazosApi.RegisterInput(UUID.randomUUID(),RetazosApi.EntryMode.NUEVO,1,d("6.4"),null,null,"","FORCE_ROLLBACK");
            assertThrows(org.springframework.dao.DataIntegrityViolationException.class,()->service.register(id,request,ADMIN));
            eq("0",repository.product(id,false).get("stock"));assertEquals(0,movements(id));assertEquals(0L,service.summary(id).get("availablePieces"));
        } finally { repository.db().execute("ALTER TABLE retazos.operation DROP CONSTRAINT test_rollback");cleanup(id); }
    }
    void cleanup(UUID id) {
        for(String table:List.of("retazos.operation","retazos.piece","retazos.material_format","inventario.movement","inventario.catalog_event"))repository.db().update("DELETE FROM "+table+" WHERE product_id=?",id);
        repository.db().update("DELETE FROM inventario.product WHERE id=?",id);
    }
    @Test void reservedPieceCannotBeCutOrDiscardedOutsideItsOrder() throws Exception {
        UUID id=aluminum("0"),piece=first(profile(id,"6.4",1));
        repository.db().update("INSERT INTO inventario.stock_reservation(id,order_id,product_id,piece_id,quantity) VALUES (?,?,?,?,1)",UUID.randomUUID(),UUID.randomUUID(),id,piece);
        assertEquals(409,assertThrows(RetazosError.class,()->service.cut(id,piece,cut("1","0",UUID.randomUUID()),WAREHOUSE)).status);
        assertEquals(409,assertThrows(RetazosError.class,()->service.discard(id,piece,new RetazosApi.ReasonInput(UUID.randomUUID(),"Descarte"),WAREHOUSE)).status);
        mvc.perform(get("/api/retazos/products/"+id+"/suggestions?extent=1").header("Authorization","Bearer warehouse")).andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
    }

}
