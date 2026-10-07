# Servicio de inventario

Portal administrativo: **http://localhost:8092**. API para web y futura app: `http://localhost:8092/api`.

## Alcance

Catálogo manual para todas las familias de productos. Cada producto tiene código único, nombre, categoría libre, unidad, descripción, proveedor, código externo opcional, ubicación en bodega, stock mínimo, estado y existencias. Se crea con stock cero; las existencias iniciales se registran mediante una entrada con motivo "Carga inicial".

Las cantidades se guardan en decimal exacto con hasta 4 decimales y 15 dígitos enteros. `62.83 UNIDAD` se conserva tal como se registra; todavía no se interpreta como planchas o retazos ni se convierte en dimensiones. Registra la unidad que puedas confirmar. Las piezas físicas y dimensiones de vidrio/aluminio se abordarán en el servicio de retazos. No se importó el Excel ni se implementó sincronización externa.

Las respuestas de la API devuelven las cantidades como cadenas decimales (por ejemplo `"62.8300"`) para preservar precisión en JavaScript. En las solicitudes puedes enviar números o cadenas decimales.

No existe borrado de productos ni edición/borrado de movimientos. Un producto solo puede desactivarse con stock cero; su historial se conserva. Su código es estable y su unidad solo puede cambiar antes del primer movimiento. El código externo se conserva como referencia para una futura integración, sin efectuar transferencias de datos.

## Permisos

| Operación | Administrador | Bodeguero | Vendedor | Chofer |
|---|---|---|---|---|
| Consultar catálogo e historial de movimientos | Sí | Sí | Sí | No |
| Crear/editar/reactivar/desactivar productos | Sí | No | No | No |
| Registrar entradas y salidas | Sí | Sí | No | No |
| Ajustar por conteo físico | Sí | No | No | No |
| Consultar cambios del catálogo | Sí | No | No | No |

El portal web permite entrar únicamente a administradores. Los permisos de otros trabajadores están disponibles por API para la futura app. Los administradores delegados tienen los mismos permisos de inventario que el principal; sus restricciones especiales pertenecen a la administración de usuarios.

La API acepta los mismos tokens Bearer del servicio de usuarios. El portal envía login/cambio de contraseña/logout a usuarios a través de inventario, sin guardar credenciales ni duplicar cuentas. El cambio obligatorio de contraseña también se aplica antes de operar inventario. Las sesiones revocadas se rechazan en la siguiente petición.

## Movimientos

- `INGRESO`: suma una cantidad positiva.
- `SALIDA`: resta una cantidad positiva; no permite stock negativo.
- `AJUSTE`: la cantidad representa el **total contado**, no la diferencia. Por ejemplo, stock 10 y conteo 4 genera delta -6 y saldo 4. Puede ajustarse a cero y exige motivo. Un ajuste sin diferencia se rechaza.

Cada operación guarda saldo anterior, saldo posterior, diferencia, motivo, referencia opcional, fecha y responsable. Un bloqueo transaccional por producto evita descontar dos veces el mismo saldo ante operaciones concurrentes. No hay todavía reservas, pedidos, ventas, compras ni múltiples bodegas con saldos separados; ubicación es un campo descriptivo.

`requestId` es un UUID que el cliente genera por operación. Si una respuesta se pierde, reenvía **el mismo UUID y los mismos datos**: se devuelve el movimiento original sin repetir el descuento. Reutilizarlo con datos diferentes o desde otro usuario devuelve 409. La web conserva el UUID al reintentar en el mismo formulario; cerrarlo o recargarlo pierde esa referencia, por lo que primero debes consultar el historial si el resultado quedó incierto.

## Endpoints

Envía `Authorization: Bearer <accessToken>` y `Content-Type: application/json` al escribir.

| Método | Ruta | Uso |
|---|---|---|
| POST | `/auth/login` | Mismas credenciales que usuarios |
| GET | `/auth/me` | Identidad actual |
| POST | `/auth/password` | Cambiar contraseña; revoca sesiones |
| POST | `/auth/logout` | Cerrar sesión |
| GET | `/products` | Catálogo paginado y filtros |
| GET | `/products/{id}` | Producto y saldo |
| POST | `/products` | Crear producto |
| PUT | `/products/{id}` | Actualizar catálogo, sin editar stock |
| POST | `/products/{id}/movements` | Entrada, salida o ajuste |
| GET | `/products/{id}/movements` | Movimientos paginados |
| GET | `/products/{id}/history` | Últimos 200 cambios del catálogo |

Filtros: `q` (código/nombre), `category` (categoría exacta), `includeInactive=true`, `lowStock=true` (saldo <= mínimo), `page=0`, `size=20` (máximo 100). Las respuestas paginadas contienen `items`, `total`, `page` y `size`.

Producto de ejemplo:

```json
{
  "code": "VID-001",
  "name": "Vidrio claro 6 mm 214 x 330",
  "category": "VIDRIO",
  "unit": "UNIDAD",
  "description": "Plancha de vidrio",
  "supplier": "Proveedor",
  "externalCode": "91012641",
  "location": "BM / Percha A",
  "minStock": 2,
  "active": true
}
```

Entrada de ejemplo (genera un UUID nuevo para cada movimiento):

```json
{
  "requestId": "59b995c7-4068-4d4e-8a1a-d4db0c793ed2",
  "type": "INGRESO",
  "quantity": 10,
  "reason": "Carga inicial verificada",
  "reference": "Conteo de bodega"
}
```

Errores: 400 validación, 401 sesión inválida, 403 permisos/cambio de clave pendiente, 404 producto inexistente, 409 stock insuficiente/duplicados/conflictos, 503 dependencia no disponible. `/actuator/health` informa salud del proceso y base de datos, sin exigir autenticación; no comprueba usuarios.

## Ejecución y pruebas

Desde la raíz:

```powershell
docker compose up -d --build
# Para ejecutar las pruebas locales con JAVA_HOME configurado:
.\scripts\test-inventario.ps1
```

Las pruebas usan PostgreSQL real; simulan usuarios para comprobar permisos, y prueban también un cliente de usuarios sin conexión. Revierten sus cambios, salvo la prueba de concurrencia que crea y elimina exclusivamente su producto de prueba. Cubren stock decimal, idempotencia, saldo insuficiente, ajustes, historial, validaciones, indisponibilidad de usuarios y salidas simultáneas.

Fuera de Docker: configura `DB_URL`, `DB_USER`, `DB_PASSWORD` y `AUTH_URL` (por defecto `http://localhost:8091`) antes de ejecutar `mvnw.cmd -f services/inventario-service/pom.xml spring-boot:run`. Dentro de Docker `AUTH_URL=http://usuarios:8081`; cada servicio puede arrancar aunque el otro esté detenido.
