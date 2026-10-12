package com.alumvid.logistica.config;

import com.alumvid.logistica.dto.CrearPedidoRequest;
import com.alumvid.logistica.dto.SincronizarChoferRequest;
import com.alumvid.logistica.repository.ChoferRepository;
import com.alumvid.logistica.repository.PedidoRepository;
import com.alumvid.logistica.service.LogisticaService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Inicializador de datos de prueba para pedidos georreferenciados y choferes en Quito.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class LogisticaDataSeeder implements CommandLineRunner {

    private final ChoferRepository choferRepository;
    private final PedidoRepository pedidoRepository;
    private final LogisticaService logisticaService;

    @Override
    public void run(String... args) {
        log.info("Modulo de Logistica listo. Base de datos limpia para pruebas operativas de rutas.");
    }
}
