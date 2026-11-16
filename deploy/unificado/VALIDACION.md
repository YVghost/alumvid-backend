# Validación del backend único

Fecha: 2026-11-16. Rama: `despliegue_test`.

## Resultado

La imagen final compila, arranca y ejecuta los flujos probados con un único proceso Java, un puerto HTTP y PostgreSQL con PostGIS como componente separado.

| Módulo | Pruebas | Fallos | Errores | Omitidas |
|---|---:|---:|---:|---:|
| Usuarios | 13 | 0 | 0 | 0 |
| Inventario | 11 | 0 | 0 | 0 |
| Retazos | 16 | 0 | 0 | 0 |
| Pedidos | 42 | 0 | 0 | 0 |
| Ubicaciones | 8 | 0 | 0 | 0 |
| Logística | 12 | 0 | 0 | 1 |
| Integración del backend único | 9 | 0 | 0 | 0 |
| Total | 111 | 0 | 0 | 1 |

110 pruebas aprobadas. La omitida requiere acceso real al proveedor Google y ya era opcional. Las pruebas de los servicios independientes pasaron en una base temporal aislada; las del backend único usan su propio PostGIS de Testcontainers.

## Imagen Docker final, limitada a 512 MiB y una CPU

Se usó `compose.unificado.yaml`, separado de los contenedores y la base del entorno original.

- Compilación Docker desde la raíz del repositorio: correcta.
- Inicio aproximado observado en la primera imagen: 11 segundos.
- 8 comprobaciones REST públicas y de protección: correctas.
- 2 handshakes WebSocket: correctos, tanto `/ws-logistica` como `/ws-logistica/websocket`.
- 240 consultas autenticadas a seis módulos, con concurrencia 4: correctas; respuesta más lenta de la última ejecución, aproximadamente 0,141 segundos.
- Flujo real por HTTP dentro del contenedor: producto → ingreso → cliente → pedido confirmado → reserva → preparación → ruta → despacho → inicio → entrega con evidencia → pedido ENTREGADO.
- Flujo real adicional: dos perfiles de 3,2 m equivalentes a una unidad de 6,4 m → consulta de disponibilidad → reserva de 1,6 m → preparación mediante corte → cancelación → retorno al inventario en su forma actual, conservando una unidad equivalente acumulada.
- Pico de memoria del cgroup de la imagen final observado después de esos flujos: 329.707.520 bytes, aproximadamente 314,43 MiB, frente al límite de 512 MiB.
- Reinicio manual con datos e historiales de migración existentes: correcto; se repitieron las comprobaciones REST y WebSocket.
- Eventos de falta de memoria y OOM kill: 0. Reinicios automáticos: 0.

Los datos ficticios de estas pruebas llevan el prefijo QA y están en la base aislada del Compose unificado. El contenedor adicional de regresión se detuvo; no se eliminó ningún volumen del entorno original.

## Límites de esta validación

Estas mediciones corresponden a pruebas locales de baja concurrencia y datos pequeños, no a una prueba prolongada de capacidad o a datos de producción. El plan, saldo, red privada, credenciales y permisos de PostGIS deben comprobarse también en Railway. Las respuestas de Google Maps y la ejecución nativa de Android/Windows contra un dominio Railway real quedan pendientes hasta disponer del despliegue remoto.

Se conservaron las rutas y el contrato de descubrimiento de las apps; no fue necesario modificar ni generar nuevos APK o ejecutables para seleccionar el nuevo servidor.

Los logs detallados están en `.cache/unificado-*.log` y los resultados JUnit en `services/*/target/surefire-reports`; ambos son artefactos locales excluidos de Git.
