package com.alumvid.ubicaciones;

import java.math.BigDecimal;
import java.nio.file.Path;
import java.util.*;
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
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest @AutoConfigureMockMvc @Import(UbicacionesIntegrationTest.Authentication.class) @Transactional
class UbicacionesIntegrationTest {
    static final PostgreSQLContainer<?> PG=new PostgreSQLContainer<>("postgres:16-alpine");
    static final AuthClient.Identity ADMIN=new AuthClient.Identity(UUID.randomUUID(),"TEST","Admin",Set.of("ADMINISTRADOR"),false,true,false);
    @TestConfiguration static class Authentication {
        @Bean @Primary AuthClient testAuth() {return new AuthClient("http://127.0.0.1:1") {@Override Identity identity(String token) {if(token.equals("Bearer admin"))return ADMIN;if(token.equals("Bearer seller"))return new Identity(UUID.randomUUID(),"TEST","Vendedor",Set.of("VENDEDOR"),false,true,false);throw new UbicacionesError(401,"Sesion invalida");}};}
    }
    @DynamicPropertySource static void database(DynamicPropertyRegistry r) {PG.start();for(String module:List.of("inventario","retazos","pedidos"))Flyway.configure().dataSource(PG.getJdbcUrl(),PG.getUsername(),PG.getPassword()).schemas(module).defaultSchema(module).locations("filesystem:"+Path.of("../"+module+"-service/src/main/resources/db/migration").toAbsolutePath().normalize().toString().replace('\\','/')).load().migrate();r.add("spring.datasource.url",PG::getJdbcUrl);r.add("spring.datasource.username",PG::getUsername);r.add("spring.datasource.password",PG::getPassword);}
    @Autowired UbicacionesService service;@Autowired JdbcTemplate db;@Autowired MockMvc mvc;
    BigDecimal d(String s) {return new BigDecimal(s);}void eq(String expected,Object actual) {assertEquals(0,d(expected).compareTo(new BigDecimal(actual.toString())));}
    UUID space(String code) {return (UUID)((Map<?,?>)service.save(null,new UbicacionesApi.Space(code,"Espacio compartido",true),ADMIN)).get("id");}
    UUID product(String stock) {UUID id=UUID.randomUUID();db.update("INSERT INTO inventario.product(id,code,name,category,unit,min_stock,stock) VALUES (?,?,?,'GENERAL','UNIDAD',0,?)",id,"TST-"+id,"Producto",d(stock));return id;}
    UbicacionesApi.Move move(UUID product,UUID from,UUID to,String quantity) {return new UbicacionesApi.Move(UUID.randomUUID(),product,from,to,quantity==null?null:d(quantity),null,"Traslado fisico");}
    UUID profile() {UUID p=product("1");db.update("UPDATE inventario.product SET pieces_managed=TRUE WHERE id=?",p);db.update("INSERT INTO retazos.material_format(product_id,kind,full_length_m,created_by) VALUES (?,'ALUMINIO',6.4,?)",p,ADMIN.id());db.update("INSERT INTO retazos.piece(id,product_id,length_m,location) VALUES (?,?,6.4,'A3')",UUID.randomUUID(),p);return p;}
    @Test void severalProductsCanShareOneSpaceAndOneProductCanUseSeveralSpaces() {UUID a=space("A3"),b=space("B3"),p=product("10"),q=product("5");service.move(move(p,null,a,"7"),ADMIN);service.move(move(p,null,b,"3"),ADMIN);service.move(move(q,null,a,"5"),ADMIN);assertEquals(2,db.queryForObject("SELECT count(*) FROM ubicaciones.placement WHERE space_id=? AND quantity>0",Integer.class,a));eq("10",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));}
    @Test void wholeStockMovesAndLeavesOriginalFreeWithoutInventoryMovement() {UUID a=space("A3"),b=space("B3"),p=product("10");service.move(move(p,null,a,null),ADMIN);service.move(move(p,a,b,null),ADMIN);eq("0",db.queryForObject("SELECT quantity FROM ubicaciones.placement WHERE product_id=? AND space_id=?",BigDecimal.class,p,a));eq("10",db.queryForObject("SELECT quantity FROM ubicaciones.placement WHERE product_id=? AND space_id=?",BigDecimal.class,p,b));assertEquals(0,db.queryForObject("SELECT count(*) FROM inventario.movement WHERE product_id=?",Integer.class,p));}
    @Test void sourcesCannotBeOverdrawnAndRetriesDoNotDuplicateTransfer() {UUID a=space("A3"),p=product("3");var move=move(p,null,a,"2");service.move(move,ADMIN);service.move(move,ADMIN);eq("2",db.queryForObject("SELECT quantity FROM ubicaciones.placement WHERE product_id=?",BigDecimal.class,p));assertEquals(409,assertThrows(UbicacionesError.class,()->service.move(move(p,null,a,"2"),ADMIN)).status);}
    @Test void stockChangesKeepLocatedQuantitiesWithinPhysicalStock() {UUID a=space("A3"),p=product("5");service.move(move(p,null,a,"4"),ADMIN);db.update("UPDATE inventario.product SET stock=2 WHERE id=?",p);eq("2",db.queryForObject("SELECT SUM(quantity) FROM ubicaciones.placement WHERE product_id=?",BigDecimal.class,p));db.update("UPDATE inventario.product SET stock=7 WHERE id=?",p);eq("5",service.product(p).get("unlocatedStock"));}
    @Test void piecesMoveIncludingReservedMaterialAndPreparedPieces() {UUID a=space("A3"),b=space("B3"),p=profile();UUID piece=db.queryForObject("SELECT id FROM retazos.piece WHERE product_id=?",UUID.class,p);db.update("INSERT INTO inventario.stock_reservation(id,order_id,product_id,piece_id,quantity) VALUES (?,?,?,?,1)",UUID.randomUUID(),UUID.randomUUID(),p,piece);service.move(move(p,a,b,null),ADMIN);assertEquals("B3",db.queryForObject("SELECT location FROM retazos.piece WHERE id=?",String.class,piece));eq("1",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));}
    @Test void occupiedSpaceCannotBeDeactivatedAndInactiveSpaceCannotReceiveStock() {UUID a=space("A3"),b=space("B3"),p=product("2");service.move(move(p,null,a,null),ADMIN);assertEquals(409,assertThrows(UbicacionesError.class,()->service.save(a,new UbicacionesApi.Space("A3","",false),ADMIN)).status);service.save(b,new UbicacionesApi.Space("B3","",false),ADMIN);assertEquals(409,assertThrows(UbicacionesError.class,()->service.move(move(p,a,b,null),ADMIN)).status);}
    @Test void implicitLegacyPieceLocationsJoinTheCatalogueWithoutChangingStock() {UUID p=profile();assertEquals(1,db.queryForObject("SELECT count(*) FROM ubicaciones.space WHERE code='A3'",Integer.class));assertEquals(1,((List<?>)((Map<?,?>)service.contents(db.queryForObject("SELECT id FROM ubicaciones.space WHERE code='A3'",UUID.class))).get("pieces")).size());eq("1",db.queryForObject("SELECT stock FROM inventario.product WHERE id=?",BigDecimal.class,p));}
    @Test void endpointsEnforceRolesAndValidation() throws Exception {mvc.perform(get("/api/ubicaciones/spaces")).andExpect(status().isUnauthorized());mvc.perform(get("/api/ubicaciones/spaces").header("Authorization","Bearer seller")).andExpect(status().isOk());mvc.perform(post("/api/ubicaciones/moves").header("Authorization","Bearer seller").contentType("application/json").content("{}")).andExpect(status().isForbidden());mvc.perform(post("/api/ubicaciones/spaces").header("Authorization","Bearer admin").contentType("application/json").content("{}")).andExpect(status().isBadRequest());}
}
