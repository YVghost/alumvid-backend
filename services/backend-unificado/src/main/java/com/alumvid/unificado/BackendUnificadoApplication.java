package com.alumvid.unificado;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.FilterType;
import org.springframework.context.annotation.FullyQualifiedAnnotationBeanNameGenerator;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/** One application context, one JVM and one HTTP port; business sources remain in their modules. */
@SpringBootConfiguration
@EnableAutoConfiguration(exclude=org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration.class)
@ComponentScan(basePackages="com.alumvid", nameGenerator=FullyQualifiedAnnotationBeanNameGenerator.class,
    excludeFilters=@ComponentScan.Filter(type=FilterType.REGEX, pattern={"com\\.alumvid\\.usuarios\\.UsuariosApplication","com\\.alumvid\\.inventario\\.InventarioServiceApplication","com\\.alumvid\\.retazos\\.RetazosApplication","com\\.alumvid\\.pedidos\\.PedidosApplication","com\\.alumvid\\.ubicaciones\\.UbicacionesApplication","com\\.alumvid\\.logistica\\.LogisticaServiceApplication","com\\.alumvid\\.inventario\\.AuthClient","com\\.alumvid\\.retazos\\.AuthClient","com\\.alumvid\\.pedidos\\.AuthClient","com\\.alumvid\\.ubicaciones\\.AuthClient","com\\.alumvid\\.logistica\\.security\\.AuthClient","com\\.alumvid\\.logistica\\.service\\.PedidosClient"}))
@EntityScan("com.alumvid.logistica.model")
@EnableJpaRepositories("com.alumvid.logistica.repository")
public class BackendUnificadoApplication {
    public static void main(String[] args) { SpringApplication.run(BackendUnificadoApplication.class,args); }
}
