package glass_inventory_api.logistica.config;

import glass_inventory_api.logistica.dto.CrearPedidoRequest;
import glass_inventory_api.logistica.model.Chofer;
import glass_inventory_api.logistica.repository.ChoferRepository;
import glass_inventory_api.logistica.repository.PedidoRepository;
import glass_inventory_api.logistica.service.LogisticaService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Configuration;

@Configuration
@RequiredArgsConstructor
@Slf4j
public class LogisticaDataSeeder implements CommandLineRunner {

    private final ChoferRepository choferRepository;
    private final PedidoRepository pedidoRepository;
    private final LogisticaService logisticaService;

    @Override
    public void run(String... args) {
        if (choferRepository.count() == 0) {
            log.info("Inicializando choferes de prueba para el módulo logístico GlassFlow...");
            logisticaService.crearChofer("Carlos Mosquera", "chofer1@glassflow.com", "+593987654321");
            logisticaService.crearChofer("Mateo Chofer", "chofer2@glassflow.com", "+593991234567");
        }

        if (pedidoRepository.count() == 0) {
            log.info("Inicializando pedidos de muestra para Quito en el módulo logístico GlassFlow...");
            logisticaService.crearPedido(CrearPedidoRequest.builder()
                    .cliente("Ventaneros Quito Norte")
                    .direccionTexto("Av. Amazonas y Orellana, Quito")
                    .latitud(-0.1807)
                    .longitud(-78.4678)
                    .build());

            logisticaService.crearPedido(CrearPedidoRequest.builder()
                    .cliente("Taller Vidrios Cumbayá")
                    .direccionTexto("Av. Interoceánica y Francisco de Orellana, Cumbayá")
                    .latitud(-0.2035)
                    .longitud(-78.4350)
                    .build());
        }
    }
}
