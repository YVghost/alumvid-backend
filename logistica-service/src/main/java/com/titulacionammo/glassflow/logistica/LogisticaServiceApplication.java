package com.titulacionammo.glassflow.logistica;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Punto de entrada del microservicio de logistica, PostGIS y telemetria en tiempo real.
 */
@SpringBootApplication
public class LogisticaServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(LogisticaServiceApplication.class, args);
    }
}
