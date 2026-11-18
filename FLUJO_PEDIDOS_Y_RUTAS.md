# Preparación de pedidos y creación de rutas

Los pedidos reservados pasan a `POR_PREPARAR`. Bodega o administración ejecutan `start-preparation` para dejarlos en `EN_PREPARACION`: se registra al actor en el historial y no se consume inventario. Al marcar el material listo (`prepare`) se realizan los cortes y el consumo físico; el pedido completo queda `LISTO`.

```mermaid
flowchart LR
  A[Por preparar] -->|Bodega inicia| B[En preparación]
  B -->|Bodega marca listo| C[Listo]
  C --> D[Retiro o ruta de entrega]
```

Se mantienen la preparación y entrega por partes, los retrasos, cancelaciones y vencimientos. La reserva sigue su plazo original: iniciar la preparación no reinicia las 72 horas. Los retiros parciales y retrasos conservan sus reglas de renovación.

La migración Flyway V6 adapta los pedidos y los estados de reanudación antes llamados RESERVADO. No cambia los estados de las líneas ni de las reservas de inventario. El filtro antiguo RESERVADO se acepta como alias de POR_PREPARAR. Los historiales anteriores permanecen intactos.

| Operación | Administrador | Bodeguero | Chofer | Vendedor |
|---|---|---|---|---|
| Iniciar preparación / marcar listo | Sí | Sí | No | No |
| Crear ruta | Sí | Sí | Para sí mismo | No |
| Consultar rutas | Todas | Todas | Propias | No |
| Reasignar, editar o eliminar rutas | Sí | No | No | No |

El chofer conserva la operación de sus entregas desde Mis rutas. La nueva creación no concede el endpoint general de despacho ni permisos para recibir devoluciones de bodega. La compensación de un despacho propio solo se permite antes de que salga a reparto.

Windows y Android reutilizan los mismos filtros, fichas y acciones. La pestaña Crear rutas aparece también en los roles BODEGUERO y CHOFER; el selector de chofer se limita al propio usuario cuando se usa la vista de chofer.

Pruebas: módulos Maven de pedidos/logística; tests Flutter de ambas apps; `python scripts/test-preparacion-rutas.py` contra el entorno local con cuentas demo. Este último crea cuentas y registros QA identificados para inspeccionar el historial; no borra los datos existentes.
