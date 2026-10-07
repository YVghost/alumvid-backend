package com.titulacionammo.glassflow.logistica.config;

import com.titulacionammo.glassflow.logistica.dto.CrearPedidoRequest;
import com.titulacionammo.glassflow.logistica.dto.SincronizarChoferRequest;
import com.titulacionammo.glassflow.logistica.repository.ChoferRepository;
import com.titulacionammo.glassflow.logistica.repository.PedidoRepository;
import com.titulacionammo.glassflow.logistica.service.LogisticaService;
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
        if (choferRepository.count() == 0) {
            log.info("Inicializando perfiles logisticos de choferes...");

            logisticaService.sincronizarOCrearChofer(SincronizarChoferRequest.builder()
                    .id(UUID.fromString("11111111-1111-1111-1111-111111111111"))
                    .nombre("Carlos Mosquera")
                    .email("carlos.chofer@glassflow.com")
                    .telefono("+593987654321")
                    .build());

            logisticaService.sincronizarOCrearChofer(SincronizarChoferRequest.builder()
                    .id(UUID.fromString("22222222-2222-2222-2222-222222222222"))
                    .nombre("Mateo Ortega")
                    .email("mateo.chofer@glassflow.com")
                    .telefono("+593991234567")
                    .build());
        }

        if (pedidoRepository.count() == 0) {
            log.info("Inicializando pedidos georreferenciados en Quito...");

            logisticaService.crearPedido(CrearPedidoRequest.builder()
                    .cliente("Ventaneria y Aluminio La Floresta")
                    .direccionTexto("Av. Amazonas y Orellana, Quito")
                    .latitud(-0.1807)
                    .longitud(-78.4678)
                    .build());

            logisticaService.crearPedido(CrearPedidoRequest.builder()
                    .cliente("Taller Vidrios Templados Cumbaya")
                    .direccionTexto("Av. Interoceanica y Francisco de Orellana, Cumbaya")
                    .latitud(-0.2035)
                    .longitud(-78.4350)
                    .build());

            logisticaService.crearPedido(CrearPedidoRequest.builder()
                    .cliente("Aluminio y Fachadas Carcelen")
                    .direccionTexto("Av. Diego de Vasquez y Carcelen, Quito Norte")
                    .latitud(-0.1000)
                    .longitud(-78.4800)
                    .build());
        }
    }
}
