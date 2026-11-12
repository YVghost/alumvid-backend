# Ubicaciones físicas

> **Sin portal web.** La interfaz de este servicio está en las apps (Windows y Android). Responsabilidad y datos: ver `ARQUITECTURA_SERVICIOS.md` en la raíz.


Servicio Spring Boot independiente, Java 21, puerto 8086 y esquema `ubicaciones`. Portal administrativo: **http://localhost:8080/ubicaciones/**. API `/api/ubicaciones`.

## Funciones

- Crear espacios con código, descripción y estado: A3, B3, percha, estante, etc.
- Consultar qué productos, piezas completas y retazos contienen.
- Compartir una ubicación entre varios productos/materiales, sin exclusividad ni restricciones por familia.
- Mantener un producto repartido entre varias ubicaciones.
- Asignar material sin ubicación y trasladar cantidades, piezas individuales o todo el material de un producto desde un origen.
- Trasladar piezas reservadas conservando sus reservas. El material en reparto no se muestra ni se traslada como presente en bodega.
- Dejar libre A3 tras trasladar todo el producto a B3 y reutilizar A3 para otro material.
- Conservar responsable, fecha y motivo del traslado. Nunca modificar stock total por un cambio de ubicación.

Los códigos son estables; para cambiar A3 por B3 se crea B3 y se traslada el material. No se puede desactivar un espacio ocupado ni usar un destino inactivo.

## Integración con stock y retazos

Las piezas usan su ubicación real en `retazos.piece`, incluyendo material preparado en bodega. Cortes y sobrantes conservan la ubicación de la fuente. Las ubicaciones descriptivas ya existentes se incorporan al catálogo; los nuevos ingresos de piezas con una ubicación no registrada también la incorporan, sin duplicar existencias.

Los productos generales usan saldos por espacio. Lo que aún no se asignó se muestra como `unlocatedStock`. Los cambios de stock se sincronizan mediante un trigger transaccional: los ingresos van a la ubicación descriptiva predeterminada del producto cuando existe; las salidas consumen primero el saldo sin ubicar y después los saldos ubicados en orden estable de código. El operador puede organizar esos saldos con traslados.

Mover saldos entre espacios no cambia automáticamente la ubicación predeterminada de futuros ingresos del producto. Si se necesita elegir el estante exacto en cada salida general, debe ampliarse el formulario de movimientos/preparación; actualmente se aplica el orden descrito. Las ubicaciones no representan múltiples bodegas con inventarios independientes.

## API y permisos

| Método/ruta bajo `/api/ubicaciones` | Uso |
|---|---|
| GET/POST `/spaces`, PUT `/spaces/{id}` | Buscar y administrar espacios |
| GET `/spaces/{id}/contents` | Material presente y piezas reservadas/preparadas |
| GET `/products`, GET `/products/{id}` | Distribución de cantidades/piezas y saldo sin ubicar |
| POST `/moves` | Traslado idempotente |
| GET `/history?productId=&page=0&size=20` | Historial |

Trasladar todo el stock de un producto de A3 a B3:

```json
{
  "requestId":"UUID-nuevo",
  "productId":"UUID-producto",
  "fromSpaceId":"UUID-A3",
  "toSpaceId":"UUID-B3",
  "reason":"Reorganización de estantes"
}
```

Productos generales: `quantity` opcional; omitirlo mueve todo el origen. `fromSpaceId: null` toma saldo sin ubicar. Piezas: `pieceIds` opcional; omitirlo mueve todas las piezas físicas del producto en el origen. Selección explícita admite hasta 200 UUID y valida su pertenencia; no se suman unidades equivalentes para fingir piezas.

Consulta: administrador, vendedor y bodeguero. Administrar espacios: administrador. Trasladar: administrador/bodeguero. Web solo administrativa; mismo login y sesiones de Usuarios.

Comparte la base PostgreSQL con los demás servicios. Los traslados bloquean productos y ubicaciones en orden estable. Los triggers mantienen cantidades coherentes aunque Pedidos/Retazos cambien stock sin pasar por este proceso HTTP.

Pruebas aisladas: `scripts/test-ubicaciones.ps1`. No incluye plano gráfico, códigos de barras, capacidades físicas, estantes exclusivos ni optimización automática de distribución.

Validacion de esta reforma: 33 pruebas de Pedidos, 8 de Ubicaciones y 16 de Retazos aprobadas. Chrome verifico el catalogo de clientes, retiros parciales, renovacion y vencimiento automatico real, retorno fisico de reparto y ubicaciones compartidas. Se usaron bases temporales separadas de la plataforma de trabajo.
