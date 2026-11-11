# Retazos y piezas físicas · AlumVid

Servicio independiente Spring Boot 3.4.3 / Java 21, puerto **8084**. Portal administrativo directo: **http://localhost:8084/**. A través del gateway: **http://localhost:8080/retazos/** (con barra final). API: `/api/retazos`.

## Reglas de negocio

El producto conserva su código y nombre existentes en inventario. Su unidad `UNIDAD` representa un perfil completo de aluminio o una plancha completa de vidrio. El desglose mantiene las piezas individuales por UUID; agruparlas en una unidad equivalente no las convierte físicamente en una pieza continua.

| Material | Referencia de 1 unidad | Equivalencia de una pieza | Medidas |
|---|---|---|---|
| Aluminio | Longitud del perfil completo | longitud / longitud completa | Metros |
| Vidrio | Área de la plancha completa | ancho × alto / área completa | Centímetros y cm² |

Ejemplos:

- Perfil completo de 6,40 m: 1 unidad. Un retazo de 3,20 m: 0,5 unidades. Ambos: 1,5 unidades.
- Dos retazos de 3,20 m: 1 unidad equivalente, **dos retazos**, cero perfiles completos. No satisfacen un corte continuo de 6,40 m.
- Plancha 183 × 244 cm: 44.652 cm² = 1 unidad. Un corte que usa **3 cm de ancho** conserva los 244 cm de alto: el sobrante es 180 × 244 cm = 43.920 cm² = 0,983606557377 unidades. Ya no se interpreta el ejemplo anterior como un recorte de esquina de 3 × 3 cm.

En esta entrega el vidrio se corta únicamente por ancho: el alto de sus piezas siempre es el alto de la referencia completa. No se admiten formas L/T ni rotación/intercambio de alto y ancho. La merma se expresa en metros para aluminio y centímetros de ancho para vidrio. Debe ser no negativa y se descuenta junto con la medida utilizada.

Cada corte deja el origen como `TRANSFORMADO` si queda un sobrante o `CONSUMIDO` si se utilizó todo. El sobrante recibe otro UUID con `parentId` apuntando a su origen. Los descartes quedan como `DESCARTADO`. El historial no se borra.

## Productos existentes y nuevos ingresos

1. Crear o localizar el producto en inventario general. Debe usar `UNIDAD` y estar activo.
2. Configurar la referencia completa: longitud de aluminio o ancho y alto del vidrio. La referencia queda fija para preservar el significado de los movimientos históricos.
3. El stock ya existente se conserva como **saldo sin desglosar**. No se inventan sus piezas ni medidas a partir del decimal del Excel.
4. Elegir `EXISTENTE` para catalogar material que ya figuraba en ese saldo: crea piezas sin incrementar stock. Solo administradores pueden hacer este desglose.
5. Elegir `NUEVO` para material realmente ingresado: crea piezas y un movimiento de entrada.
6. Al cortar, utilizar, descartar o reconciliar, el servicio actualiza tanto las piezas como el saldo general y su movimiento.

No registrar un retazo existente como `NUEVO`: duplicaría el material. Un registro `EXISTENTE` no puede superar el saldo sin desglosar. Si el conteo físico no coincide con una cantidad antigua redondeada, el administrador puede reconciliar el saldo sin desglosar con motivo obligatorio. Indicar cero significa que ya no queda material pendiente de catalogar; genera el ajuste auditado que corresponda. No modifica las piezas ya registradas.

No se importó el Excel ni se cambió la nomenclatura. La equivalencia requiere medidas de referencia confirmadas por producto.

## Stock, precisión y coherencia

- El total es `(medida sin desglosar + suma de medidas físicas disponibles) / medida de referencia`.
- Se suman longitudes o áreas **antes de dividir y redondear**. No se acumulan porcentajes ya redondeados.
- Stock y movimientos usan `NUMERIC(27,12)`; las medidas aceptan hasta cuatro decimales. La precisión extendida conserva las cantidades anteriores sin convertirlas a otras unidades.
- Los decimales se devuelven como cadenas para conservar precisión en JavaScript. El porcentaje por pieza se devuelve con ocho decimales.
- Se bloquea el producto durante las operaciones. Dos peticiones simultáneas no pueden consumir la misma pieza.
- Toda escritura lleva `requestId` UUID. Reenviar exactamente la misma operación con el mismo usuario devuelve su resultado original; reutilizarlo con otros datos devuelve 409.
- La web mantiene ese identificador mientras reintentas sin modificar/cerrar el formulario. Si cerraste o recargaste después de perder una respuesta, consulta el historial antes de repetirla.
- Al habilitar gestión por piezas se bloquean los movimientos genéricos de ese producto en inventario. Sus ingresos, cortes, descartes y ajustes se registran desde retazos para no romper el desglose.
- No puede cambiarse la unidad de un producto gestionado por piezas. Su código sigue estable y su desactivación continúa exigiendo stock cero.

## Arquitectura de esta entrega

Se mantiene una única base PostgreSQL y un esquema propio `retazos`. `inventario-service` aplica la migración **V2__piece_inventory.sql** antes de iniciar retazos; por eso Compose espera su healthcheck.

El adaptador `InventoryLedger` integra las tablas de inventario en **la misma transacción PostgreSQL** que las piezas y la operación. Si falla cualquier escritura, se revierten todas. Esta es una dependencia explícita de la base compartida: hoy evita inconsistencias de una llamada HTTP confirmada seguida de un fallo local. No constituye aislamiento de bases por microservicio. Si se separan las bases en el futuro, este adaptador necesitará reemplazarse por un protocolo de integración con confirmación/reintentos; no bastará con sustituirlo por un POST dentro de la transacción.

Usuarios se consulta por HTTP para validar la sesión y sus roles. No se leen sus tablas. Retazos puede operar sin que el proceso de inventario esté disponible si su esquema ya está migrado y usuarios/base están disponibles. Los otros productos no configurados siguen usando inventario normalmente.

## Permisos

| Operación | Administrador | Bodeguero | Vendedor | Chofer |
|---|---|---|---|---|
| Consultar piezas, equivalencias, sugerencias e historial | Sí | Sí | Sí | No |
| Configurar referencia completa | Sí | No | No | No |
| Ingresar material nuevo, cortar y descartar | Sí | Sí | No | No |
| Desglosar stock existente y reconciliarlo | Sí | No | No | No |

El portal web es administrativo. La API está preparada para los demás roles en la app. Se aplica el cambio obligatorio de contraseña temporal. No se agregan cuentas ni credenciales predeterminadas propias de retazos. A través del gateway, el portal puede aprovechar la sesión ya existente de AlumVid.

## API

Usar `Authorization: Bearer <token de usuarios>` y JSON. Base `/api/retazos`.

| Método | Ruta | Función |
|---|---|---|
| GET | `/products?q=&page=0&size=20` | Productos con nomenclatura actual y estado de gestión por piezas |
| PUT | `/products/{id}/format` | Definir unidad completa; repetir mismos valores no duplica configuración |
| GET | `/products/{id}/summary` | Total equivalente, piezas completas, retazos, saldo sin desglosar y grupos por medidas |
| GET | `/products/{id}/pieces?state=DISPONIBLE&page=0&size=20` | Piezas individuales; `state=` incluye todos los estados |
| POST | `/products/{id}/pieces` | Registrar piezas nuevas o existentes; quantity de 1 a 200 |
| POST | `/products/{id}/pieces/{pieceId}/cut` | Usar/cortar una pieza, con merma opcional |
| POST | `/products/{id}/pieces/{pieceId}/discard` | Descartar conservando historial |
| POST | `/products/{id}/reconcile` | Ajustar exclusivamente el saldo sin desglosar |
| GET | `/products/{id}/suggestions?extent=3.2` | Piezas aptas: metros para aluminio; centímetros de ancho para vidrio |
| GET | `/products/{id}/operations?page=0&size=20` | Historial paginado, responsable, motivo y saldos |

Las sugerencias muestran retazos aptos antes que material completo, ordenados por menor tamaño suficiente. Un corte sobre una pieza completa se rechaza si ya existe un retazo disponible que lo permite. Esta selección usa medidas físicas, no solo la suma de unidades equivalentes. Las reservas y asignaciones se coordinan desde Pedidos.

Configuración de aluminio:

```json
{ "kind": "ALUMINIO", "fullLengthM": "6.40" }
```

Configuración de vidrio:

```json
{ "kind": "VIDRIO", "fullWidthCm": "183", "fullHeightCm": "244" }
```

Registro de dos retazos de aluminio (genera un UUID distinto por operación):

```json
{
  "requestId": "11395640-4798-4475-97b3-98a6a9c232b0",
  "mode": "NUEVO",
  "quantity": 2,
  "lengthM": "3.2",
  "location": "Percha A",
  "reason": "Recepción de dos piezas"
}
```

Para material ya contabilizado usar `"mode": "EXISTENTE"`. Para vidrio reemplazar `lengthM` por `widthCm` y `heightCm`.

Corte de aluminio:

```json
{
  "requestId": "c625fb47-5763-4bce-b5c9-449a5b353870",
  "usedLengthM": "1.20",
  "wasteLengthM": "0.003",
  "reason": "Corte para orden de taller"
}
```

Para vidrio usar `usedWidthCm` y `wasteWidthCm`. Consumir toda la medida disponible no crea un sobrante de tamaño cero. El descarte requiere `requestId` y `reason`. Reconciliación: `requestId`, `unallocatedUnits` y `reason`.

Login/cambio de clave/logout se ofrecen en `/auth/login`, `/auth/me`, `/auth/password`, `/auth/logout` del mismo prefijo. Se reenvían al servicio de usuarios.

## Ejecución y validación

Antes de iniciar Compose, configura `DB_PASSWORD` en `.env` con la clave de PostgreSQL y comprueba `DB_NAME` y `DB_USER`. Compose utiliza `DB_*`; las variables antiguas `POSTGRES_*` no sustituyen esta configuracion. Conserva las credenciales de la base existente.

```powershell
# JAVA_HOME: JDK 21 o superior; compilar los módulos antes de sus Dockerfiles existentes.
.\mvnw.cmd -pl services/usuarios-service,services/inventario-service,services/gateway-service -am package -DskipTests
docker compose up -d --build retazos-service
# Para servir el portal a través de un gateway ya preparado:
docker compose up -d --build --no-deps gateway-service
```

El servicio de retazos tiene Dockerfile multi-stage y se compila durante su build. El gateway conserva sus otras rutas; si quieres utilizar también logística, inicia ese servicio conforme a su configuración existente.

Pruebas aisladas:

```powershell
.\scripts\test-retazos.ps1
```

Requieren Docker con contenedores Linux. Testcontainers inicia PostgreSQL temporal, migra inventario y retazos, y no usa `.env` ni la base real. Se verifican equivalencias, vidrio por ancho, porcentajes, stock existente sin duplicación, merma, prioridad de retazos, idempotencia, permisos, concurrencia, rollback y conservación de datos durante V1→V2. La integración de inventario añade una prueba para bloquear movimientos genéricos de productos gestionados por piezas.

Pedidos y reservas se gestionan ahora desde `pedidos-service`; las piezas reservadas no admiten cortes o descartes manuales. No se incluyeron importación automática del Excel ni cambios en logística. Este servicio deja la trazabilidad de piezas preparada para esas integraciones.

Validacion realizada: 16 pruebas de retazos y 11 de inventario aprobadas, mas un flujo completo en Chrome mediante el gateway (login, equivalencias, cortes, stock existente y vista movil). Se uso PostgreSQL temporal sin modificar datos reales.

Las piezas preparadas por Pedidos se conservan con sus medidas en PREPARADO; al entregar pasan a ENTREGADO. Cancelacion o vencimiento devuelve a DISPONIBLE solo lo no entregado y presente fisicamente, sin reconstruir la pieza fuente ni recuperar merma. Ubicaciones permite moverlas conservando su identidad.
