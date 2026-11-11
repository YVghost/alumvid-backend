package com.alumvid.pedidos;

import java.time.Clock;
import java.util.UUID;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.*;
import org.springframework.stereotype.Component;

@Configuration @EnableScheduling
class ReservationClock {
    @Bean Clock orderClock() {return Clock.systemUTC();}
}
@Component
@ConditionalOnProperty(name="app.expiry-enabled",havingValue="true",matchIfMissing=true)
class ExpiryJob {
    private final PedidosService service;private final JdbcTemplate db;private final Clock clock;
    ExpiryJob(PedidosService service,JdbcTemplate db,Clock clock) {this.service=service;this.db=db;this.clock=clock;}
    @Scheduled(fixedDelayString="${app.expiry-poll-ms:1000}",initialDelay=1000)
    public void expire() {
        for(UUID id:db.query("SELECT id FROM pedidos.sale_order WHERE expires_at<=? AND state NOT IN ('CANCELADO','VENCIDO','ENTREGADO') ORDER BY expires_at LIMIT 100",(r,n)->r.getObject(1,UUID.class),java.sql.Timestamp.from(clock.instant()))) {
            try {service.expire(id);}catch(RuntimeException e){LoggerFactory.getLogger(ExpiryJob.class).error("No se pudo procesar el vencimiento del pedido {}; se reintentara",id);}
        }
    }
}
