package com.alumvid.pedidos;

import java.math.BigDecimal;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import com.fasterxml.jackson.databind.JsonSerializer;
import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.databind.SerializerProvider;

@SpringBootApplication
public class PedidosApplication {
    public static void main(String[] args) { SpringApplication.run(PedidosApplication.class,args); }
    @Bean Jackson2ObjectMapperBuilderCustomizer decimals() {
        return builder->builder.serializerByType(BigDecimal.class,new JsonSerializer<BigDecimal>() {
            @Override public void serialize(BigDecimal value,JsonGenerator generator,SerializerProvider provider) throws java.io.IOException {
                generator.writeString(value.toPlainString());
            }
        });
    }
}
