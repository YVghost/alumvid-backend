package com.alumvid.unificado;

import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.springframework.boot.autoconfigure.flyway.FlywayMigrationStrategy;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

@Configuration
public class ModuleMigrations {
    @Bean FlywayMigrationStrategy moduleMigrationStrategy(DataSource dataSource) {
        return ignored -> {
            // init.sql is idempotent and enables PostGIS before Hibernate and the dependent migrations.
            new ResourceDatabasePopulator(new ClassPathResource("db/bootstrap/init.sql")).execute(dataSource);
            for (String module : new String[]{"usuarios","inventario","retazos","pedidos","ubicaciones"}) {
                Flyway.configure().dataSource(dataSource).schemas(module).defaultSchema(module)
                    .locations("classpath:db/modules/"+module).cleanDisabled(true).load().migrate();
            }
        };
    }
}
