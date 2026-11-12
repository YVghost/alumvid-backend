# Arquitectura: qué hace cada servicio

Cada servicio es dueño de sus datos y es el único que los modifica. Las apps
(Windows y Android) son la única interfaz: los paneles web se eliminaron.

| Servicio | Responsabilidad | Dueño de |
|---|---|---|
| **usuarios** (8081) | Cuentas, roles, sesiones, contraseñas y auditoría de seguridad | `usuarios.*` |
| **inventario** (8082) | Catálogo, stock y movimientos. A mano solo: recepción de compra e inventario físico (conteo) | `inventario.product`, `movement` |
| **retazos** (8084) | Piezas con medida (perfiles y vidrios): alta, descarte, búsqueda por medida y ficha de cada pieza | `retazos.*` |
| **ubicaciones** (8086) | Espacios de bodega y traslados de material entre ellos | `ubicaciones.*` |
| **pedidos** (8085) | Ventas: clientes, reserva automática, preparación (corta piezas y descuenta stock), entregas, devoluciones, bandeja de entregas | `pedidos.*` |
| **logística** (8083) | Rutas, paradas, choferes en ruta, GPS y prueba de entrega (foto + firma) | `logistica.*` |
| **gateway** (8080) | Solo enruta `/api/**` y expone `/platform-info` | — |

## Flujo de un pedido a domicilio

1. **Vendedor** crea el pedido con la ubicación en el mapa → pedidos reserva el material.
2. El pedido aparece solo en **Rutas → Por asignar** ("En preparación").
3. **Bodega** pulsa *Preparar*: se cortan las piezas y se descuenta el inventario automáticamente.
4. El pedido pasa a "Listo para ruta". **Administración** crea la ruta con un chofer **disponible**
   (activo y sin ruta en curso) o lo agrega a una ruta pendiente. Logística le pide a pedidos que
   registre el despacho (custodia del material) y guarda la carga de la parada.
5. Mientras la ruta está pendiente se puede **modificar la carga**, quitar paradas o cambiar el chofer.
6. El **chofer** inicia y entrega con foto, firma y GPS. Pedidos marca la entrega.
7. La ruta se **cierra sola** al terminar sus paradas; lo no entregado queda "por recibir" en bodega.

Reglas que valida el backend (no solo la app):
- No se cambia el chofer de una ruta en curso.
- Un chofer en ruta no recibe ni inicia otra ruta.
- Las salidas de inventario no se registran a mano: las genera el flujo de pedidos.

## Permisos

| Rol | Puede |
|---|---|
| ADMINISTRADOR | Todo. Gestiona usuarios que no son administradores y ve la auditoría |
| Cuenta maestra | Además gestiona a otros administradores y otorga ese rol |
| VENDEDOR | Pedidos y clientes; consulta inventario, piezas y bodega |
| BODEGUERO | Preparar, entregar en local, recibir devoluciones, recepciones de compra, traslados y descarte de piezas |
| CHOFER | Sus rutas: iniciar, entregar con evidencia, marcar no entregado y reintentar |

## Acoplamiento pendiente

Pedidos, retazos y ubicaciones aún leen y actualizan tablas de inventario y retazos en la
misma base para reservar y cortar dentro de una sola transacción. Llevar esas escrituras a
APIs de inventario/retazos es el siguiente paso de limpieza.

Verificación de punta a punta: `python scripts/verificar-flujo-entregas.py`.
