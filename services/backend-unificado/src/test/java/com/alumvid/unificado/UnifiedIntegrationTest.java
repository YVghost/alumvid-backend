package com.alumvid.unificado;

import com.alumvid.usuarios.Users;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.http.HttpMethod;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(classes=BackendUnificadoApplication.class,properties={
    "app.master.identification=1725958449","app.master.password=Test-master-2026!",
    "alumvid.security.jwt.secret=only-for-isolated-integration-tests-2026-long-signing-key",
    "app.expiry-enabled=false"})
@AutoConfigureMockMvc
class UnifiedIntegrationTest {
    static final PostgreSQLContainer<?> PG=new PostgreSQLContainer<>(DockerImageName.parse("postgis/postgis:16-3.4").asCompatibleSubstituteFor("postgres"));
    @DynamicPropertySource static void database(DynamicPropertyRegistry r) {
        PG.start();r.add("spring.datasource.url",PG::getJdbcUrl);r.add("spring.datasource.username",PG::getUsername);r.add("spring.datasource.password",PG::getPassword);
    }
    @Autowired MockMvc mvc;@Autowired ObjectMapper json;@Autowired JdbcTemplate db;@Autowired Users users;@Autowired PasswordEncoder passwords;
    JsonNode call(String method,String path,String token,Object body,int expected) throws Exception {
        var request=MockMvcRequestBuilders.request(HttpMethod.valueOf(method),path);
        if(token!=null)request.header("Authorization","Bearer "+token);
        if(body!=null)request.contentType("application/json").content(json.writeValueAsString(body));
        var response=mvc.perform(request).andReturn().getResponse();
        assertEquals(expected,response.getStatus(),method+" "+path+": "+response.getContentAsString());
        return response.getContentAsString().isBlank()?json.nullNode():json.readTree(response.getContentAsString());
    }
    String login(String id) throws Exception {return call("POST","/api/v1/auth/login",null,Map.of("identification",id,"password","Test-master-2026!"),200).path("token").asText();}
    String admin() throws Exception{return login("1725958449");}
    Users.User employee(Users.Role role,boolean temporary) {
        var id=UUID.randomUUID();var u=new Users.User(id,"T-"+id.toString().substring(0,20),id+"@alumvid.test",null,"Test "+role,passwords.encode("Test-master-2026!"),Set.of(role),false,true,temporary);users.insert(u);return u;
    }
    static final List<String> PROTECTED=List.of("/api/products","/api/retazos/products","/api/pedidos/orders","/api/ubicaciones/spaces","/api/v1/logistica/rutas");
    @Test void allModulesShareOneContextAndExistingMigrationHistories() throws Exception {
        call("GET","/actuator/health",null,null,200);
        assertEquals("AlumVid API Gateway",call("GET","/platform-info",null,null,200).path("service").asText());
        var token=admin();for(var path:PROTECTED)call("GET",path,token,null,200);
        for(var module:List.of("usuarios","inventario","retazos","pedidos","ubicaciones"))assertTrue(db.queryForObject("SELECT count(*) FROM "+module+".flyway_schema_history WHERE success",Integer.class)>0);
        assertNotNull(db.queryForObject("SELECT postgis_version()",String.class));
    }
    @Test void unauthenticatedAndRevokedSessionsCannotCrossModules() throws Exception {
        for(var path:PROTECTED)call("GET",path,null,null,401);
        var employee=employee(Users.Role.ADMINISTRADOR,false);var token=login(employee.identification());
        for(var path:PROTECTED)call("GET",path,token,null,200);
        call("POST","/api/auth/logout",token,null,204);
        for(var path:PROTECTED)call("GET",path,token,null,401);
    }
    @Test void temporaryPasswordsAreBlockedEverywhereUntilChanged() throws Exception {
        var employee=employee(Users.Role.ADMINISTRADOR,true);var token=login(employee.identification());
        for(var path:PROTECTED)call("GET",path,token,null,403);
        call("GET","/api/auth/me",token,null,200);
        call("POST","/api/auth/password",token,Map.of("currentPassword","Test-master-2026!","newPassword","Test-new-password-2026!"),204);
    }
    @Test void liveAccountStateAndRolesAreHonoredWithoutHttp() throws Exception {
        var employee=employee(Users.Role.VENDEDOR,false);var token=login(employee.identification());
        for(var path:PROTECTED.subList(0,4))call("GET",path,token,null,200);
        call("GET","/api/v1/logistica/rutas",token,null,403);
        call("POST","/api/products",token,Map.of(),403);
        db.update("UPDATE usuarios.app_user SET active=false WHERE id=?",employee.id());
        for(var path:PROTECTED)call("GET",path,token,null,401);
    }
    @Test void moduleValidationAndErrorResponsesDoNotInterfere() throws Exception {
        var token=admin();
        call("POST","/api/products",token,Map.of(),400);
        call("POST","/api/pedidos/clients",token,Map.of(),400);
        call("POST","/api/ubicaciones/spaces",token,Map.of(),400);
        call("POST","/api/v1/logistica/rutas",token,Map.of(),400);
        call("GET","/api/products/"+UUID.randomUUID(),token,null,404);
        call("GET","/api/pedidos/orders/"+UUID.randomUUID(),token,null,404);
    }
    JsonNode product(String token) throws Exception {
        return call("POST","/api/products",token,Map.of("code","T-"+UUID.randomUUID(),"name","Perfil prueba","category","ALUMINIO","unit","UNIDAD","minStock",0,"active",true),201);
    }
    @Test void retazosAndLocationsUpdateTheSameInventory() throws Exception {
        var token=admin();var id=product(token).path("id").asText();
        call("PUT","/api/retazos/products/"+id+"/format",token,Map.of("kind","ALUMINIO","fullLengthM","6.4"),200);
        call("POST","/api/retazos/products/"+id+"/pieces",token,Map.of("requestId",UUID.randomUUID(),"mode","NUEVO","quantity",2,"lengthM","3.2","location","A3","reason","Prueba integrada"),200);
        assertEquals(0,new java.math.BigDecimal("1").compareTo(new java.math.BigDecimal(call("GET","/api/products/"+id,token,null,200).path("stock").asText())));
        call("GET","/api/retazos/products/"+id+"/summary",token,null,200);
        call("POST","/api/ubicaciones/spaces",token,Map.of("code","A-"+UUID.randomUUID(),"description","Prueba","active",true),200);
        call("GET","/api/ubicaciones/products/"+id,token,null,200);
    }
    @Test void availabilityReservationPreparationAndCancellationRestoreStock() throws Exception {
        var token=admin();var id=product(token).path("id").asText();
        call("POST","/api/products/"+id+"/movements",token,Map.of("requestId",UUID.randomUUID(),"type","INGRESO","quantity",4,"reason","Prueba integrada"),200);
        var client=call("POST","/api/pedidos/clients",token,Map.of("name","Cliente prueba","active",true),200).path("id").asText();
        var lines=List.of(Map.of("productId",id,"quantity",2,"unitPrice",5));
        call("POST","/api/pedidos/availability",token,Map.of("lines",lines),200);
        var created=call("POST","/api/pedidos/orders",token,Map.of("requestId",UUID.randomUUID(),"clientId",client,"externallyConfirmed",true,"deliveryMode","RETIRO","lines",lines),200);
        var order=created.path("order").path("id").asText();assertFalse(order.isBlank());
        for(var action:List.of("confirm","prepare","cancel"))call("POST","/api/pedidos/orders/"+order+"/"+action,token,Map.of("requestId",UUID.randomUUID(),"reason","Prueba "+action),200);
        assertEquals("CANCELADO",call("GET","/api/pedidos/orders/"+order,token,null,200).path("order").path("state").asText());
        assertEquals(0,new java.math.BigDecimal("4").compareTo(new java.math.BigDecimal(call("GET","/api/products/"+id,token,null,200).path("stock").asText())));
    }
    @Test void logisticsUsesLiveDriversThroughTheLocalAdapter() throws Exception {
        var employee=employee(Users.Role.CHOFER,false);var token=admin();
        var drivers=call("GET","/api/v1/logistica/choferes",token,null,200);
        assertTrue(drivers.toString().contains(employee.id().toString()));
        call("GET","/ws-logistica/info",null,null,200);
    }
    @Test void logisticsDispatchAndDeliveryCloseTheCommercialOrderWithoutHttp() throws Exception {
        var token=admin();var driver=employee(Users.Role.CHOFER,false);
        var product=product(token).path("id").asText();
        call("POST","/api/products/"+product+"/movements",token,Map.of("requestId",UUID.randomUUID(),"type","INGRESO","quantity",3,"reason","Entrega integrada"),200);
        var client=call("POST","/api/pedidos/clients",token,Map.of("name","Cliente entrega","active",true),200).path("id").asText();
        var request=new HashMap<String,Object>();request.put("requestId",UUID.randomUUID());request.put("clientId",client);request.put("externallyConfirmed",true);
        request.put("deliveryMode","ENTREGA");request.put("deliveryAddress","Quito prueba");request.put("deliveryLatitude",-0.2);request.put("deliveryLongitude",-78.5);
        request.put("lines",List.of(Map.of("productId",product,"quantity",2,"unitPrice",5)));
        var order=call("POST","/api/pedidos/orders",token,request,200).path("order").path("id").asText();
        for(var action:List.of("confirm","prepare"))call("POST","/api/pedidos/orders/"+order+"/"+action,token,Map.of("requestId",UUID.randomUUID(),"reason","Prueba "+action),200);
        var route=call("POST","/api/v1/logistica/rutas",token,Map.of("codigoRuta","TEST-"+UUID.randomUUID(),"choferId",driver.id(),"pedidos",List.of(Map.of("pedidoId",order))),201);
        assertEquals(1,route.path("paradas").size());
        var dispatch=route.path("paradas").get(0).path("id").asText();
        var driverToken=login(driver.identification());
        call("POST","/api/v1/logistica/despachos/"+dispatch+"/aceptar-inicio",driverToken,null,200);
        var delivered=call("POST","/api/v1/logistica/despachos/"+dispatch+"/cerrar-entrega",driverToken,
            Map.of("fotoPodUrl","data:image/png;base64,dGVzdA==","firmaUrl","data:image/png;base64,dGVzdA==","latitud",-0.2,"longitud",-78.5),200);
        assertEquals("ENTREGADO",delivered.path("estado").asText());
        assertEquals("ENTREGADO",call("GET","/api/pedidos/orders/"+order,token,null,200).path("order").path("state").asText());
    }

}
