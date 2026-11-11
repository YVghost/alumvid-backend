# Pedidos confirmados y entregas por partes

Portal administrativo: **http://localhost:8080/pedidos/**. API `/api/pedidos`, puerto interno 8085.

## Alcance acordado

Solo ingresan pedidos ya confirmados y con factura pagada **fuera del sistema**. El operador declara `externallyConfirmed: true`; puede guardar una referencia externa. No se comprueban ni procesan pagos, anticipos, crédito, impuestos, descuentos o facturación tributaria: están fuera del alcance. Los precios siguen siendo manuales/referenciales hasta disponer de la tabla de trabajos.

La consulta de disponibilidad sigue disponible sin crear pedidos, clientes, reservas ni movimientos. Usa stock libre y medidas físicas; retazos compatibles primero, material completo después. Al registrar se verifica nuevamente bajo bloqueo y se reserva lo disponible. Los faltantes quedan por línea en `PENDIENTE_MATERIAL`. No se prepara material hasta tener reservado todo el pedido.

La ficha comercial permanece inmutable: para corregirla, cancelar y registrar otra. `BORRADOR`/`confirm` se conservan para compatibilidad con fichas anteriores, pero los nuevos pedidos entran confirmados y reservados o pendientes de material.

## Clientes y receptores

Catálogo independiente dentro del dominio de Pedidos: nombre, identificación opcional única, teléfono, correo, dirección habitual y activo/inactivo. Permite crear, buscar, editar y desactivar sin borrar. Los nuevos pedidos por API requieren `clientId` activo.

Cada pedido conserva una fotografía del nombre del cliente. Cambiar el catálogo no cambia sus fichas antiguas. El receptor inicial y el receptor de cada entrega se guardan únicamente en el historial del pedido, no como nuevos clientes.

## Preparación, retiro y reparto parciales

Cada operación puede seleccionar cantidades de líneas concretas. Se distinguen:

- Material crudo reservado y aún no preparado.
- Material preparado que permanece en bodega, retenido para el cliente.
- Material enviado a reparto, aún no recibido por el cliente.
- Cantidad entregada y cantidad devuelta a existencias.

Preparar descuenta el consumo y merma del stock libre, genera piezas de salida en estado `PREPARADO` y conserva los sobrantes. Si se prepara solo una parte de una fuente, las reservas de los cortes restantes pasan al sobrante real. No se mezclan dos retazos para prometer una pieza continua más larga.

Retirar/entregar puede hacerse en varios lotes. Lo pendiente conserva su reserva. Entregar no descuenta nuevamente el inventario. Para domicilio, primero se registra qué cantidad sale a reparto y después cuál se entrega. Cada lote admite receptor y motivo propios.

Vidrio: cm, alto nominal fijo y cortes por ancho. Aluminio: longitud en metros. Las piezas preparadas se entregan enteras; no se permite entregar media pieza ya cortada. Productos generales admiten las fracciones de su unidad hasta cuatro decimales.

## Plazo renovable de 72 horas

1. Se inicia al registrar/confirmar el pedido.
2. Cada retiro o entrega **parcial** reinicia 72 horas para todo el pendiente.
3. Cada retraso registrado reinicia 72 horas. Reanudar no vuelve a reiniciarlas.
4. Consultar, reintentar disponibilidad, preparar y despachar no amplían el plazo.
5. Un pedido vencido no puede renovarse mediante una entrega o retraso tardío.

El trabajador automático comprueba vencimientos cada segundo, procesa cada pedido en su propia transacción y recupera pendientes al volver a arrancar. Cuando el servicio está detenido no puede ejecutar devoluciones físicas; al reiniciar procesa los vencidos. Si una devolución falla se revierte y se reintenta, sin duplicar entradas.

## Cancelación y vencimiento

Se liberan las reservas de material crudo. El preparado **no entregado y todavía en bodega** regresa automáticamente al inventario con sus dimensiones actuales: completo si sigue completo, retazo si ya está cortado. No se reconstruye la fuente original ni se recupera la merma de corte. Lo ya entregado no se devuelve.

Lo enviado a reparto se conserva pendiente de retorno, sin ofrecerlo como presente en bodega. Tras recepción física se registra `receive-return`, que devuelve exclusivamente esa cantidad. Se admiten recepciones por partes y reintentos idempotentes.

Pedidos preparados antes de esta reforma sin piezas de salida medidas se identifican con `legacy_return_review`: su devolución exige revisión física y no inventa dimensiones. La migración conserva sus datos y otorga 72 horas a los pedidos antiguos activos desde la actualización; nuevos pedidos usan la fecha real de confirmación.

## API

| Método/ruta bajo `/api/pedidos` | Función |
|---|---|
| GET `/products`, POST `/availability` | Consultar catálogo y disponibilidad sin pedido |
| GET/POST `/clients`, PUT `/clients/{id}` | Catálogo de clientes |
| POST `/orders` | Registrar pedido confirmado, asociado a cliente |
| GET `/orders`, GET `/orders/{id}` | Listado, vencimiento, líneas, reservas, preparados e historial |
| POST `/orders/{id}/retry` | Revisar faltantes y reservar, sin renovar plazo |
| POST `/orders/{id}/prepare` | Preparar las cantidades seleccionadas |
| POST `/orders/{id}/dispatch` | Enviar a reparto cantidades preparadas |
| POST `/orders/{id}/deliver` | Retiro/entrega de cantidades seleccionadas |
| POST `/orders/{id}/delay`, `/resume` | Retraso documentado y reanudación |
| POST `/orders/{id}/cancel` | Liberar y devolver lo pendiente en bodega |
| POST `/orders/{id}/receive-return` | Recepción de devoluciones desde reparto |

Crear:

```json
{
  "requestId": "UUID-nuevo",
  "clientId": "UUID-del-cliente",
  "externallyConfirmed": true,
  "externalInvoiceReference": "Referencia opcional",
  "deliveryMode": "RETIRO",
  "receiverName": "Opcional, solo histórico",
  "lines": [{"productId":"UUID-producto","quantity":"2","lengthM":"1.6","wasteExtent":"0.003","unitPrice":"0"}]
}
```

Para `ENTREGA` se requiere `deliveryAddress`. Vidrio usa `widthCm`/`heightCm` en lugar de `lengthM`. Productos generales omiten dimensiones y merma; pieza completa omite dimensiones y exige material completo real. Hasta 50 líneas, 200 piezas por línea. Precios y decimales se expresan como cadenas.

Preparar/entregar/despachar/recibir un lote:

```json
{
  "requestId": "UUID-nuevo",
  "reason": "Retira una parte del pedido",
  "receiverName": "Receptor de este lote, opcional",
  "lines": [{"lineId":"UUID-linea","quantity":"1"}]
}
```

Omitir `lines` opera sobre todo lo disponible para esa acción; la web exige seleccionar cantidades explícitas. Duplicados, cantidades negativas, piezas fraccionadas, líneas ajenas y excesos se rechazan. El mismo `requestId` con datos y actor iguales devuelve el resultado original. Otro contenido con ese UUID devuelve 409.

## Permisos e integración

Web solo administrativa. API: administrador/vendedor gestionan clientes y pedidos; administrador/bodeguero preparan, despachan, entregan y reciben devoluciones; los tres consultan y registran retrasos. Chofer sigue usando su dominio de logística. Se aplican las sesiones de Usuarios y el cambio obligatorio de contraseña.

PostgreSQL compartido: stock, reservas, piezas, lotes e historial participan en la misma transacción; se bloquea el pedido y sus productos en orden estable. Separar las bases requerirá rediseñar este contrato mediante eventos y compensaciones. Logística aún no sincroniza automáticamente rutas/conductores/evidencias con la ficha comercial; reparto y entrega son registros administrativos.

Pruebas: `scripts/test-pedidos.ps1`, PostgreSQL temporal con Testcontainers. La batería cubre renovaciones, vencimiento, entregas parciales, recepción de reparto, concurrencia, medidas reales, merma e idempotencia.

Validacion de esta reforma: 33 pruebas de Pedidos, 8 de Ubicaciones y 16 de Retazos aprobadas. Chrome verifico el catalogo de clientes, retiros parciales, renovacion y vencimiento automatico real, retorno fisico de reparto y ubicaciones compartidas. Se usaron bases temporales separadas de la plataforma de trabajo.
