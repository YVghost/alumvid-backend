# Integración Mateo

Rama de trabajo: `mateo_integracion`, creada desde `services` e integrada con `origin/develop` (`ae53366`). `main`, `develop` y `services` no se publican ni se modifican con esta entrega.

## Cambios

- Se reúnen los siete servicios, administrador Flutter, móvil con cambio de contraseña temporal y telemetría/optimización de rutas.
- Gateway en 8080; usuarios 8081; inventario 8082; logística 8083; retazos 8084; pedidos 8085; ubicaciones 8086; PostgreSQL 5433.
- Se conserva el administrador web en `/`, además del administrador Flutter. `/platform-info` contiene los metadatos del gateway.
- El endpoint heredado DELETE de usuarios ahora desactiva y revoca sesiones, conservando usuario y referencias de auditoría. Solo lo permite el principal.
- Se admiten identificaciones alfanuméricas; no se impone cédula ecuatoriana.
- Las consultas de pedidos, retazos y ubicaciones informan fallos y permiten abrir los portales con todos sus formularios. Las vistas Flutter aún no replican todos esos formularios.
- Logout móvil elimina solamente las preferencias de autenticación.

## Configuración privada

Se importó la clave de Maps y variables operativas desde el `.env` de `ProyectoTitulacionV2`. Se conservaron conexión y credenciales de la base existente, administrador y JWT para no alterar el acceso a sus datos. No se copian bases de datos de la carpeta descargada.

`.env` y `config/flutter.local.json` se excluyen de Git. Para otra computadora crear `.env` desde `.env.example` y `config/flutter.local.json` desde `config/flutter.example.json`; completar las claves por un canal privado. Las claves de cliente Maps son visibles en la aplicación compilada/navegador y requieren las restricciones apropiadas en Google Cloud. Los valores embebidos en código se retiraron; el historial previo de Git no se reescribió.

## Ejecución

```powershell
docker compose -f compose.yaml up -d --build
.\scripts\iniciar-admin.ps1
.\scripts\iniciar-movil.ps1 -LaunchEmulator
```

Windows requiere Visual Studio con Desarrollo para el escritorio con C++. Se puede probar el administrador en Android con `-Device emulator-5554`. Los lanzadores comprueban dependencias y compilan desde fuentes; no requieren el ejecutable Debug de otra computadora.

## Límites que no resuelve un merge

Los pedidos comerciales y los pedidos de logística siguen siendo entidades diferentes. No existe todavía sincronización automática transaccional entre entregas logísticas y entregas parciales/reservas comerciales; no debe darse por completada una venta comercial por cerrar una ruta. Las operaciones comerciales completas siguen disponibles en `/pedidos/`.

La fotografía del móvil todavía tiene captura simulada. GPS, permisos, evidencias reales y recuperación sin conexión requieren una prueba de campo. Una compilación o prueba unitaria no certifica estos flujos.

Antes de promover a `main` deben completarse y validarse esos flujos según el alcance acordado. Esta rama permite revisar la integración sin reemplazar la rama principal.

## Verificación realizada

- Suite backend completa: usuarios, inventario, retazos, pedidos, ubicaciones y logística. La llamada real a Google Routes queda como prueba opcional con `GOOGLE_ROUTES_LIVE_TEST=true`; no se incluye una clave en el test ni se requiere una API externa para la validación normal.
- Análisis Flutter de ambas aplicaciones; pruebas de login, configuración, decimales y conservación de preferencias.
- Compilación de las imágenes Docker y de ambos APK Debug con configuración local.
- Plataforma levantada: `python scripts/smoke-platform.py` comprueba 19 condiciones HTTP, acceso autenticado, portales y fecha inválida, sin crear pedidos/productos. Revoca su sesión al terminar.
- Respaldo previo de PostgreSQL en `.cache/integracion/database-before-integration.dump` (local e ignorado).

No se certifica el ejecutable Windows: este equipo no tiene instalado el componente C++ de Visual Studio requerido. Se compiló el administrador para Android. La prueba HTTP no sustituye una prueba de campo GPS/entrega ni valida restricciones/cuotas de Google Cloud.
