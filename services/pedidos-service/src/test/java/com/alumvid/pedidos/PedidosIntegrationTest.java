package com.alumvid.pedidos;

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
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.*;
import org.testcontainers.containers.PostgreSQLContainer;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties="app.expiry-enabled=false") @AutoConfigureMockMvc @Import(PedidosIntegrationTest.Authentication.class)
@Transactional
class PedidosIntegrationTest {
    static final PostgreSQLContainer<?> PG=new PostgreSQLContainer<>("postgres:16-alpine");
    static final AuthClient.Identity ADMIN=identity("ADMINISTRADOR",false),SELLER=identity("VENDEDOR",false),WAREHOUSE=identity("BODEGUERO",false);
    static AuthClient.Identity identity(String role,boolean temp) {return new AuthClient.Identity(UUID.randomUUID(),"TEST","Operador",Set.of(role),false,true,temp);}
    @TestConfiguration static class Authentication {
        @Bean @Primary AuthClient fakeAuth(){return new AuthClient("http://127.0.0.1:1") {@Override Identity identity(String token){return switch(token){case "Bearer admin"->ADMIN;case "Bearer seller"->SELLER;case "Bearer warehouse"->WAREHOUSE;case "Bearer driver"->PedidosIntegrationTest.identity("CHOFER",false);case "Bearer temporary"->PedidosIntegrationTest.identity("ADMINISTRADOR",true);default->throw new PedidosError(401,"Token invalido");};}};}
    }
    @DynamicPropertySource static void database(DynamicPropertyRegistry r) {
        PG.start();for(String module:List.of("inventario","retazos"))Flyway.configure().dataSource(PG.getJdbcUrl(),PG.getUsername(),PG.getPassword()).schemas(module).defaultSchema(module).locations("filesystem:"+Path.of("../"+module+"-service/src/main/resources/db/migration").toAbsolutePath().normalize().toString().replace('\\','/')).load().migrate();
        r.add("spring.datasource.url",PG::getJdbcUrl);r.add("spring.datasource.username",PG::getUsername);r.add("spring.datasource.password",PG::getPassword);
    }
    @Autowired CommercialShipments shipping;@Autowired PedidosService service;@Autowired JdbcTemplate db;@Autowired MockMvc mvc;
    BigDecimal d(String s){return new BigDecimal(s);}void eq(String expected,Object actual){assertEquals(0,d(expected).compareTo(new BigDecimal(actual.toString())));}
    UUID product(String stock){UUID id=UUID.randomUUID();db.update("INSERT INTO inventario.product(id,code,name,category,unit,min_stock,stock) VALUES (?,?,?,'ACCESORIOS','UNIDAD',0,?)",id,"TST-"+id,"Producto",d(stock));return id;}
    UUID material(boolean glass){UUID id=product("0");db.update("UPDATE inventario.product SET pieces_managed=TRUE WHERE id=?",id);db.update("INSERT INTO retazos.material_format(product_id,kind,full_length_m,full_width_cm,full_height_cm,created_by) VALUES (?,?,?,?,?,?)",id,glass?"VIDRIO":"ALUMINIO",glass?null:d("6.4"),glass?d("183"):null,glass?d("244"):null,ADMIN.id());return id;}
    UUID piece(UUID id,String extent,boolean glass){UUID piece=UUID.randomUUID();db.update("INSERT INTO retazos.piece(id,product_id,length_m,width_cm,height_cm,location) VALUES (?,?,?,?,?,'Bodega A')",piece,id,glass?null:d(extent),glass?d(extent):null,glass?d("244"):null);db.update("UPDATE inventario.product SET stock=stock+? WHERE id=?",d(extent).divide(glass?d("183"):d("6.4"),12,java.math.RoundingMode.HALF_UP),id);return piece;}
    PedidosApi.Line line(UUID id,String qty){return new PedidosApi.Line(id,d(qty),null,null,null,null,d("10"));}
    PedidosApi.Line cut(UUID id,String qty,String extent){return new PedidosApi.Line(id,d(qty),d(extent),null,null,d("0"),d("12"));}
    UUID create(List<PedidosApi.Line> lines,boolean delivery){var result=service.create(new PedidosApi.Create(UUID.randomUUID(),"Cliente prueba",delivery?PedidosApi.Delivery.ENTREGA:PedidosApi.Delivery.RETIRO,delivery?"Calle y referencia":"","Persona opcional","",lines),SELLER);return id(result);}
    UUID id(Map<String,Object> data){return UUID.fromString(((Map<?,?>)data.get("order")).get("id").toString());}
    Map<String,Object> act(UUID id,String name){return service.action(id,name,new PedidosApi.Action(UUID.randomUUID(),"Motivo de prueba"),ADMIN);}
    String state(UUID id){return ((Map<?,?>)service.get(id).get("order")).get("state").toString();}
    long count(String table){return db.queryForObject("SELECT count(*) FROM "+table,Long.class);}
    @Test void consultationDoesNotCreateOrdersOrReserveAnything(){UUID p=product("5");long orders=count("pedidos.sale_order"),reservations=count("inventario.stock_reservation");assertEquals(true,service.availability(List.of(line(p,"2"))).get("available"));assertEquals(orders,count("pedidos.sale_order"));assertEquals(reservations,count("inventario.stock_reservation"));}
    @Test void deliveryRequiresAddressAndReceiverIsOptional(){UUID p=product("2");var invalid=new PedidosApi.Create(UUID.randomUUID(),"Cliente",PedidosApi.Delivery.ENTREGA,"","","",List.of(line(p,"1")));assertEquals(400,assertThrows(PedidosError.class,()->service.create(invalid,SELLER)).status);UUID order=create(List.of(line(p,"1")),true);assertEquals("RESERVADO",state(order));}
    @Test void confirmationReservesWithoutConsumingAndPreparationConsumesExactlyOnce(){UUID p=product("5"),order=create(List.of(line(p,"2")),false);act(order,"confirm");eq("5",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));assertEquals("RESERVADO",state(order));eq("3",((List<Map<String,Object>>)service.products("",0,100).get("items")).stream().filter(x->p.equals(x.get("id"))).findFirst().orElseThrow().get("availableStock"));var request=new PedidosApi.Action(UUID.randomUUID(),"Preparacion");service.action(order,"prepare",request,WAREHOUSE);service.action(order,"prepare",request,WAREHOUSE);eq("3",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));assertEquals(1,db.queryForObject("SELECT count(*) FROM inventario.movement WHERE product_id=?",Integer.class,p));act(order,"deliver");assertEquals("ENTREGADO",state(order));assertEquals(409,assertThrows(PedidosError.class,()->act(order,"cancel")).status);}
    @Test void partialMaterialIsReservedAndRetryAfterIntakeCompletes(){UUID p=product("2"),order=create(List.of(line(p,"3")),false);act(order,"confirm");assertEquals("PENDIENTE_MATERIAL",state(order));eq("2",db.queryForObject("SELECT reserved_quantity FROM pedidos.order_line WHERE order_id=?",BigDecimal.class,order));db.update("UPDATE inventario.product SET stock=3 WHERE id=?",p);act(order,"retry");assertEquals("RESERVADO",state(order));eq("3",db.queryForObject("SELECT SUM(quantity) FROM inventario.stock_reservation WHERE order_id=? AND state='ACTIVA'",BigDecimal.class,order));}
    @Test void repeatedProductLinesCannotOverpromise(){UUID p=product("3");var result=service.availability(List.of(line(p,"2"),line(p,"2")));assertEquals(false,result.get("available"));var lines=(List<Map<String,Object>>)result.get("lines");eq("1",lines.get(1).get("missingQuantity"));}
    @Test void reservationBlocksAnotherOrderAndCancelReleasesIt(){UUID p=product("2"),a=create(List.of(line(p,"2")),false),b=create(List.of(line(p,"2")),false);act(a,"confirm");act(b,"confirm");assertEquals("PENDIENTE_MATERIAL",state(b));act(a,"cancel");act(b,"retry");assertEquals("RESERVADO",state(b));}
    @Test void suitableRemnantIsSelectedBeforeFullPiece(){UUID p=material(false),full=piece(p,"6.4",false),remnant=piece(p,"3.2",false);UUID order=create(List.of(cut(p,"1","2")),false);act(order,"confirm");assertEquals(remnant,db.queryForObject("SELECT piece_id FROM pedidos.allocation WHERE order_id=?",UUID.class,order));act(order,"prepare");eq("1.1875",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));assertEquals("DISPONIBLE",db.queryForObject("SELECT state FROM retazos.piece WHERE id=?",String.class,full));assertEquals(1,db.queryForObject("SELECT count(*) FROM retazos.piece WHERE parent_id=? AND length_m=1.2",Integer.class,remnant));}
    @Test void fullPieceIsUsedWhenNoRemnantFits(){UUID p=material(false);piece(p,"1.6",false);UUID full=piece(p,"6.4",false);UUID order=create(List.of(cut(p,"1","3.2")),false);act(order,"confirm");assertEquals(full,db.queryForObject("SELECT piece_id FROM pedidos.allocation WHERE order_id=?",UUID.class,order));}
    @Test void twoSmallRemnantsDoNotFitOneLongProfile(){UUID p=material(false);piece(p,"3.2",false);piece(p,"3.2",false);assertEquals(false,service.availability(List.of(cut(p,"1","6.4"))).get("available"));}
    @Test void multipleCutsShareOneReservedSourceAndLeftoverReturnsAfterPreparation(){UUID p=material(false),source=piece(p,"6.4",false);UUID order=create(List.of(cut(p,"2","1.6")),false);act(order,"confirm");assertEquals(1,db.queryForObject("SELECT count(*) FROM inventario.stock_reservation WHERE order_id=? AND state='ACTIVA'",Integer.class,order));act(order,"prepare");eq("0.5",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));assertEquals(1,db.queryForObject("SELECT count(*) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE' AND length_m=3.2",Integer.class,p));}
    @Test void glassKeepsHeightAndUsesWidthAndWaste(){UUID p=material(true);piece(p,"183",true);var l=new PedidosApi.Line(p,d("1"),null,d("3"),d("244"),d("0.1"),d("15"));UUID order=create(List.of(l),false);act(order,"confirm");act(order,"prepare");eq("179.9",db.queryForObject("SELECT width_cm FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE'",BigDecimal.class,p));eq("244",db.queryForObject("SELECT height_cm FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE'",BigDecimal.class,p));eq("0.983060109290",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));}
    @Test void glassDifferentHeightIsRejected(){UUID p=material(true);assertEquals(400,assertThrows(PedidosError.class,()->service.availability(List.of(new PedidosApi.Line(p,d("1"),null,d("3"),d("100"),null,d("10"))))).status);}
    @Test void unallocatedStockCannotBePromisedAsKnownPieces(){UUID p=material(false);db.update("UPDATE inventario.product SET stock=1 WHERE id=?",p);db.update("UPDATE retazos.material_format SET unallocated_measure=6.4 WHERE product_id=?",p);assertEquals(false,service.availability(List.of(cut(p,"1","1"))).get("available"));}
    @Test void deliveryStatesAndDelayRequireValidTransitions(){UUID p=product("2"),order=create(List.of(line(p,"1")),true);act(order,"confirm");act(order,"delay");assertEquals("RETRASADO",state(order));act(order,"resume");assertEquals("RESERVADO",state(order));act(order,"prepare");assertEquals(409,assertThrows(PedidosError.class,()->act(order,"deliver")).status);act(order,"dispatch");act(order,"deliver");assertEquals("ENTREGADO",state(order));}
    @Test void cancellingPreparedMaterialReturnsOnlyActualPieces(){UUID p=material(false);piece(p,"6.4",false);UUID order=create(List.of(cut(p,"1","3.2")),false);act(order,"confirm");act(order,"prepare");act(order,"cancel");eq("1",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));assertEquals("CANCELADO",state(order));}
    @Test void idempotencyRejectsDifferentPayload(){UUID p=product("5"),order=create(List.of(line(p,"1")),false);var request=UUID.randomUUID();service.action(order,"confirm",new PedidosApi.Action(request,"Uno"),SELLER);assertEquals(409,assertThrows(PedidosError.class,()->service.action(order,"confirm",new PedidosApi.Action(request,"Dos"),SELLER)).status);}
    @Test void permissionsAndValidationAreEnforced() throws Exception {mvc.perform(get("/api/pedidos/products")).andExpect(status().isUnauthorized());mvc.perform(get("/api/pedidos/products").header("Authorization","Bearer driver")).andExpect(status().isForbidden());mvc.perform(get("/api/pedidos/products").header("Authorization","Bearer temporary")).andExpect(status().isForbidden());mvc.perform(post("/api/pedidos/orders").header("Authorization","Bearer warehouse").contentType("application/json").content("{}" )).andExpect(status().isForbidden());mvc.perform(post("/api/pedidos/availability").header("Authorization","Bearer seller").contentType("application/json").content("{\"lines\":[]}")).andExpect(status().isBadRequest());}
    @Test @Transactional(propagation=Propagation.NOT_SUPPORTED) void historyFailureRollsBackPhysicalConsumption(){UUID p=material(false);UUID source=piece(p,"6.4",false),order=create(List.of(cut(p,"1","3.2")),false);act(order,"confirm");db.execute("ALTER TABLE pedidos.order_event ADD CONSTRAINT reject_prepare_test CHECK(action<>'PREPARE')");try{assertThrows(org.springframework.dao.DataIntegrityViolationException.class,()->act(order,"prepare"));}finally{db.execute("ALTER TABLE pedidos.order_event DROP CONSTRAINT reject_prepare_test");}eq("1",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));assertEquals("DISPONIBLE",db.queryForObject("SELECT state FROM retazos.piece WHERE id=?",String.class,source));assertEquals("RESERVADO",state(order));}
    @Test @Transactional(propagation=Propagation.NOT_SUPPORTED)
    void concurrentOrdersCannotReserveSameMaterial() throws Exception {UUID p=product("1"),a=create(List.of(line(p,"1")),false),b=create(List.of(line(p,"1")),false);var pool=Executors.newFixedThreadPool(2);try{List<Callable<Map<String,Object>>> tasks=List.of(()->act(a,"confirm"),()->act(b,"confirm"));var futures=pool.invokeAll(tasks);for(var f:futures)f.get();assertEquals(1,db.queryForObject("SELECT count(*) FROM inventario.stock_reservation WHERE product_id=? AND state='ACTIVA'",Integer.class,p));assertEquals(Set.of("RESERVADO","PENDIENTE_MATERIAL"),Set.of(state(a),state(b)));}finally{pool.shutdownNow();}}
    UUID lineId(UUID order) {return db.queryForObject("SELECT id FROM pedidos.order_line WHERE order_id=? ORDER BY position LIMIT 1",UUID.class,order);}
    Map<String,Object> batch(UUID order,String action,String quantity) {return service.action(order,action,new PedidosApi.Action(UUID.randomUUID(),"Lote de prueba",List.of(new PedidosApi.BatchLine(lineId(order),d(quantity))),"Receptor de este lote"),ADMIN);}
    void due(UUID order) {db.update("UPDATE pedidos.sale_order SET expires_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE id=?",order);}
    @Test void partialPickupRenewsDeadlineAndPreservesRemainingReservation() {
        UUID p=product("5"),order=create(List.of(line(p,"5")),false);
        db.update("UPDATE pedidos.sale_order SET expires_at=CURRENT_TIMESTAMP+INTERVAL '1 hour' WHERE id=?",order);
        batch(order,"prepare","2");assertEquals("PARCIAL",state(order));
        assertTrue(db.queryForObject("SELECT expires_at<CURRENT_TIMESTAMP+INTERVAL '2 hours' FROM pedidos.sale_order WHERE id=?",Boolean.class,order));
        batch(order,"deliver","1");assertEquals("PARCIAL",state(order));
        assertTrue(db.queryForObject("SELECT expires_at>CURRENT_TIMESTAMP+INTERVAL '71 hours' FROM pedidos.sale_order WHERE id=?",Boolean.class,order));
        eq("3",db.queryForObject("SELECT SUM(quantity) FROM inventario.stock_reservation WHERE order_id=? AND state='ACTIVA'",BigDecimal.class,order));
        batch(order,"prepare","3");batch(order,"deliver","4");assertEquals("ENTREGADO",state(order));eq("0",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
    }
    @Test void delayRenewsButResumeDoesNotRenewAgain() {
        UUID p=product("1"),order=create(List.of(line(p,"1")),false);db.update("UPDATE pedidos.sale_order SET expires_at=CURRENT_TIMESTAMP+INTERVAL '1 hour' WHERE id=?",order);
        act(order,"delay");var deadline=db.queryForObject("SELECT expires_at FROM pedidos.sale_order WHERE id=?",java.time.OffsetDateTime.class,order);
        assertTrue(deadline.toInstant().isAfter(java.time.Instant.now().plusSeconds(71*3600)));act(order,"resume");assertEquals(deadline,db.queryForObject("SELECT expires_at FROM pedidos.sale_order WHERE id=?",java.time.OffsetDateTime.class,order));
    }
    @Test void expiryReturnsOnlyUndeliveredPreparedGoodsAndFreesRawReservations() {
        UUID p=product("10"),order=create(List.of(line(p,"5")),false);batch(order,"prepare","3");batch(order,"deliver","1");due(order);service.expire(order);service.expire(order);
        assertEquals("VENCIDO",state(order));eq("9",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
        eq("2",db.queryForObject("SELECT returned_quantity FROM pedidos.order_line WHERE order_id=?",BigDecimal.class,order));
        assertEquals(0,db.queryForObject("SELECT count(*) FROM inventario.stock_reservation WHERE order_id=? AND state='ACTIVA'",Integer.class,order));
    }
    @Test void returnPreservesActualCutAndDoesNotRestoreSawWasteOrOriginalSource() {
        UUID p=material(false),source=piece(p,"6.4",false);
        var requested=new PedidosApi.Line(p,d("2"),d("1.6"),null,null,d("0.1"),d("10"));UUID order=create(List.of(requested),false);batch(order,"prepare","1");act(order,"cancel");
        eq("0.984375",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
        assertEquals("TRANSFORMADO",db.queryForObject("SELECT state FROM retazos.piece WHERE id=?",String.class,source));
        assertEquals(2,db.queryForObject("SELECT count(*) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE'",Integer.class,p));
        assertEquals(1,db.queryForObject("SELECT count(*) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE' AND length_m=1.6",Integer.class,p));
    }
    @Test void expirationWaitsForTransitGoodsToPhysicallyReturn() {
        UUID p=product("2"),order=create(List.of(line(p,"2")),true);act(order,"prepare");batch(order,"dispatch","1");due(order);service.expire(order);
        eq("1",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
        eq("1",db.queryForObject("SELECT SUM(dispatched_quantity) FROM pedidos.fulfillment_item WHERE order_id=?",BigDecimal.class,order));
        var command=new PedidosApi.Action(UUID.randomUUID(),"Recepcion fisica en bodega");service.action(order,"receive-return",command,WAREHOUSE);service.action(order,"receive-return",command,WAREHOUSE);
        eq("2",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
    }
    @Test void latePickupOrDelayCannotResurrectExpiredReservation() {
        UUID p=product("1"),order=create(List.of(line(p,"1")),false);act(order,"prepare");due(order);
        assertEquals(409,assertThrows(PedidosError.class,()->act(order,"delay")).status);assertEquals(409,assertThrows(PedidosError.class,()->act(order,"deliver")).status);
        service.expire(order);assertEquals("VENCIDO",state(order));
    }
    @Test void severalLinesCanShareOneSourceAcrossPartialPreparations() {
        UUID p=material(false);piece(p,"6.4",false);UUID order=create(List.of(cut(p,"1","1.6"),cut(p,"1","1.6")),false);act(order,"prepare");eq("0.5",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
        act(order,"cancel");eq("1",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
    }
    @Test void unconfirmedOrdersAreRejectedAndClientNamesAreHistoricalSnapshots() {
        UUID p=product("2"),client=UUID.randomUUID();db.update("INSERT INTO pedidos.client(id,name) VALUES (?,'Nombre original')",client);
        var request=new PedidosApi.Create(UUID.randomUUID(),null,PedidosApi.Delivery.RETIRO,"","Receptor solo historico","",List.of(line(p,"1")),client,false,"Referencia externa");
        assertEquals(400,assertThrows(PedidosError.class,()->service.create(request,SELLER)).status);
        var order=service.create(new PedidosApi.Create(UUID.randomUUID(),null,PedidosApi.Delivery.RETIRO,"","Receptor solo historico","",List.of(line(p,"1")),client,true,"Referencia externa"),SELLER);
        db.update("UPDATE pedidos.client SET name='Nombre actualizado' WHERE id=?",client);
        assertEquals("Nombre original",db.queryForObject("SELECT client_name FROM pedidos.sale_order WHERE id=?",String.class,id(order)));
        assertEquals("RESERVADO",state(id(order)));
    }
    @Test void deliveringMoreThanPreparedOrFractionalPieceIsRejected() {
        UUID p=material(false);piece(p,"6.4",false);UUID order=create(List.of(cut(p,"2","1.6")),false);batch(order,"prepare","1");
        assertEquals(409,assertThrows(PedidosError.class,()->batch(order,"deliver","2")).status);
        assertEquals(400,assertThrows(PedidosError.class,()->batch(order,"deliver","0.5")).status);
    }
    @Test void clientEndpointsRequireCommercialRoleAndOrderRequiresExternalConfirmation() throws Exception {
        mvc.perform(post("/api/pedidos/clients").header("Authorization","Bearer warehouse").contentType("application/json").content("{\"name\":\"Cliente\",\"active\":true}")).andExpect(status().isForbidden());
        mvc.perform(post("/api/pedidos/orders").header("Authorization","Bearer seller").contentType("application/json").content("{\"requestId\":\""+UUID.randomUUID()+"\",\"deliveryMode\":\"RETIRO\",\"lines\":[]}")).andExpect(status().isBadRequest());
    }

    @Test void cancelledGlassReturnsCutDimensionsAndNeverReturnsWaste() {
        UUID p=material(true);piece(p,"183",true);var requested=new PedidosApi.Line(p,d("1"),null,d("3"),d("244"),d("0.1"),d("0"));UUID order=create(List.of(requested),false);act(order,"prepare");act(order,"cancel");
        eq("0.999453551913",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
        assertEquals(1,db.queryForObject("SELECT count(*) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE' AND width_cm=3 AND height_cm=244",Integer.class,p));
    }
    @Test void aPreparedWholeProfileReturnsAsAWholeProfile() {
        UUID p=material(false);piece(p,"6.4",false);UUID order=create(List.of(line(p,"1")),false);act(order,"prepare");due(order);service.expire(order);
        eq("1",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
        assertEquals(1,db.queryForObject("SELECT count(*) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE' AND length_m=6.4",Integer.class,p));
    }
    @Test void expiryWorkerRecoversDueReservationsOnItsNextPass() {
        UUID p=product("2"),order=create(List.of(line(p,"2")),false);act(order,"prepare");due(order);
        new ExpiryJob(service,db,java.time.Clock.systemUTC()).expire();assertEquals("VENCIDO",state(order));eq("2",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
    }
    @Test @Transactional(propagation=Propagation.NOT_SUPPORTED)
    void cancellationAndPickupRaceCannotBothReturnAndDeliverTheSameGoods() throws Exception {
        UUID p=product("2"),order=create(List.of(line(p,"2")),false);act(order,"prepare");var executor=Executors.newFixedThreadPool(2);
        try {List<Callable<Object>> tasks=List.of(()->{try{return batch(order,"deliver","1");}catch(PedidosError e){assertEquals(409,e.status);return null;}},()->act(order,"cancel"));for(var f:executor.invokeAll(tasks))f.get();
            BigDecimal stock=db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p),delivered=db.queryForObject("SELECT delivered_quantity FROM pedidos.order_line WHERE order_id=?",BigDecimal.class,order);eq("2",stock.add(delivered));assertEquals("CANCELADO",state(order));
        } finally {executor.shutdownNow();}
    }


    UUID link(UUID order,String quantity){
        UUID line=db.queryForObject("SELECT id FROM pedidos.order_line WHERE order_id=?",UUID.class,order);
        service.action(order,"dispatch",new PedidosApi.Action(UUID.randomUUID(),"Despacho",List.of(new PedidosApi.BatchLine(line,d(quantity))),null),ADMIN);
        UUID shipment=UUID.randomUUID(),dispatch=UUID.randomUUID();
        db.update("INSERT INTO pedidos.commercial_shipment(id,order_id,request_id,fingerprint,driver_id,logistics_order_id,dispatch_id,route_id,reason,created_by,created_by_name) VALUES (?,?,?,'test',?,?,?,?, 'Prueba',?,'Operador')",shipment,order,UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID(),dispatch,UUID.randomUUID(),ADMIN.id());
        BigDecimal need=d(quantity);
        for(var f:db.queryForList("SELECT id,dispatched_quantity FROM pedidos.fulfillment_item WHERE order_id=? ORDER BY created_at,id",order)){
            BigDecimal assigned=db.queryForObject("SELECT COALESCE(SUM(i.quantity),0) FROM pedidos.shipment_item i JOIN pedidos.commercial_shipment s ON s.id=i.shipment_id WHERE i.fulfillment_id=? AND s.state IN ('EN_REPARTO','RETORNO_PENDIENTE')",BigDecimal.class,f.get("id"));
            BigDecimal take=need.min(((BigDecimal)f.get("dispatched_quantity")).subtract(assigned));
            if(take.signum()>0){db.update("INSERT INTO pedidos.shipment_item VALUES (?,?,?)",shipment,f.get("id"),take);need=need.subtract(take);}if(need.signum()==0)break;
        }
        return shipment;
    }
    UUID dispatch(UUID shipment){return db.queryForObject("SELECT dispatch_id FROM pedidos.commercial_shipment WHERE id=?",UUID.class,shipment);}
    void complete(UUID shipment){db.queryForObject("SELECT pedidos.complete_commercial_dispatch(?) IS NULL",Boolean.class,dispatch(shipment));}
    void cancelShipment(UUID shipment){db.queryForObject("SELECT pedidos.cancel_commercial_dispatch(?,'Cancelado en viaje') IS NULL",Boolean.class,dispatch(shipment));}

    @Test void linkedDeliveryUpdatesExactQuantityOnceAndRenewsPartialDeadline(){
        UUID p=product("10"),order=create(List.of(line(p,"10")),true);act(order,"prepare");UUID shipment=link(order,"4");
        db.update("UPDATE pedidos.sale_order SET expires_at=CURRENT_TIMESTAMP+interval '1 hour' WHERE id=?",order);
        complete(shipment);complete(shipment);
        eq("4",db.queryForObject("SELECT delivered_quantity FROM pedidos.order_line WHERE order_id=?",BigDecimal.class,order));
        eq("0",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));assertEquals("PARCIAL",state(order));
        assertTrue(db.queryForObject("SELECT expires_at>CURRENT_TIMESTAMP+interval '71 hours' FROM pedidos.sale_order WHERE id=?",Boolean.class,order));
        assertEquals(1,db.queryForObject("SELECT count(*) FROM pedidos.order_event WHERE order_id=? AND action='ENTREGA_LOGISTICA'",Integer.class,order));
    }
    @Test void twoShipmentsOfOneLineCanArriveOutOfOrder(){
        UUID p=product("10"),order=create(List.of(line(p,"10")),true);act(order,"prepare");UUID first=link(order,"4"),second=link(order,"6");
        complete(second);eq("6",db.queryForObject("SELECT delivered_quantity FROM pedidos.order_line WHERE order_id=?",BigDecimal.class,order));assertEquals("EN_REPARTO",state(order));
        complete(first);assertEquals("ENTREGADO",state(order));
    }
    @Test void cancellingShipmentDoesNotMakeMaterialAvailableUntilPhysicalReceipt(){
        UUID p=product("5"),order=create(List.of(line(p,"5")),true);act(order,"prepare");UUID shipment=link(order,"2");cancelShipment(shipment);
        eq("2",db.queryForObject("SELECT SUM(dispatched_quantity) FROM pedidos.fulfillment_item WHERE order_id=?",BigDecimal.class,order));
        shipping.receive(shipment,new PedidosApi.Action(UUID.randomUUID(),"Recibido físicamente"),ADMIN);
        shipping.receive(shipment,new PedidosApi.Action(UUID.randomUUID(),"Reintento"),ADMIN);
        eq("0",db.queryForObject("SELECT SUM(dispatched_quantity) FROM pedidos.fulfillment_item WHERE order_id=?",BigDecimal.class,order));
        eq("0",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));assertEquals("LISTO",state(order));
    }
    @Test void linkedPhysicalReturnAfterOrderCancellationRestoresOnlyItsCutPiece(){
        UUID p=material(false);piece(p,"6.4",false);UUID order=create(List.of(cut(p,"2","1.6")),true);act(order,"prepare");UUID shipment=link(order,"1");cancelShipment(shipment);
        // Simular la cancelación del pedido sin necesitar tablas de logística en esta prueba aislada.
        db.update("UPDATE pedidos.sale_order SET state='CANCELADO' WHERE id=?",order);
        shipping.receive(shipment,new PedidosApi.Action(UUID.randomUUID(),"Pieza recibida"),ADMIN);
        eq("0.75",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));
        assertEquals(1,db.queryForObject("SELECT count(*) FROM retazos.piece WHERE product_id=? AND state='DISPONIBLE' AND length_m=1.6",Integer.class,p));
        eq("1",db.queryForObject("SELECT SUM(returned_quantity) FROM pedidos.fulfillment_item WHERE order_id=?",BigDecimal.class,order));
    }
    @Test void manualDeliveryCannotConsumeQuantitiesInLinkedShipment(){
        UUID p=product("2"),order=create(List.of(line(p,"2")),true);act(order,"prepare");link(order,"1");
        assertEquals(409,assertThrows(PedidosError.class,()->act(order,"deliver")).status);
    }
    @Test void linkedShipmentActionsRequireWarehouseRole() throws Exception {
        mvc.perform(post("/api/pedidos/orders/"+UUID.randomUUID()+"/shipments").header("Authorization","Bearer seller").contentType("application/json").content("{}" )).andExpect(status().isForbidden());
        mvc.perform(post("/api/pedidos/shipments/"+UUID.randomUUID()+"/receive-return").header("Authorization","Bearer driver").contentType("application/json").content("{}" )).andExpect(status().isForbidden());
    }

    @Test void linkedDeliveryRejectsDelayWithoutConsumingAnything(){
        UUID p=product("2"),order=create(List.of(line(p,"2")),true);act(order,"prepare");UUID shipment=link(order,"2");act(order,"delay");
        assertThrows(org.springframework.dao.DataAccessException.class,()->complete(shipment));
    }
    @Test void linkedDeliveryRequiresConsistentPreparedCustody(){
        UUID p=material(false);piece(p,"6.4",false);UUID order=create(List.of(cut(p,"1","1.6")),true);act(order,"prepare");UUID shipment=link(order,"1");
        db.update("UPDATE retazos.piece SET state='DESCARTADO' WHERE id IN (SELECT piece_id FROM pedidos.fulfillment_item WHERE order_id=?)",order);
        assertThrows(org.springframework.dao.DataAccessException.class,()->complete(shipment));
    }

    @Test void physicalReturnDoesNotSilentlyResumeADelayedOrder(){
        UUID p=product("2"),order=create(List.of(line(p,"2")),true);act(order,"prepare");UUID shipment=link(order,"2");cancelShipment(shipment);act(order,"delay");
        shipping.receive(shipment,new PedidosApi.Action(UUID.randomUUID(),"Recepción física"),ADMIN);
        assertEquals("RETRASADO",state(order));act(order,"resume");assertEquals("LISTO",state(order));
    }
}
