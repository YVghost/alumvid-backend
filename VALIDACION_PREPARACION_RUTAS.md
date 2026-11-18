# Validación de preparación y rutas

Fecha: 2026-11-17.

- Pedidos: 45 pruebas aprobadas, incluyendo inicio sin consumo, transición a listo, idempotencia, devoluciones, entregas parciales y rechazo de operaciones de bodega desde chofer.
- Logística: 17 pruebas ejecutadas; 16 aprobadas y una consulta externa de Google omitida. Se comprobó creación por administración/bodega, creación propia por chofer, rechazo de asignación ajena y conservación de permisos administrativos.
- Windows: 11 pruebas aprobadas.
- Android: 19 pruebas aprobadas, con los dos escenarios opcionales de servidor omitidos en la suite unitaria.
- Backend unificado de despliegue: nueve pruebas de integración aprobadas después de sincronizar los cambios.
- Análisis Flutter sin incidencias en los clientes normales y en los clientes de despliegue que conservan Local/Railway.
- Prueba HTTP real: 35 comprobaciones aprobadas, incluidos POR_PREPARAR → EN_PREPARACION → LISTO, creación de rutas desde bodega y desde un chofer y rechazo de rutas ajenas.

La migración V6 se aplicó sobre la base local existente sin borrar datos. Los registros QA de la prueba HTTP se conservaron para revisión y llevan prefijo QA-PREP. Las contraseñas y sesiones no se incorporan al repositorio.

La validación remota en Railway requiere desplegar la rama correspondiente. Los archivos de despliegue continúan exclusivamente en despliegue_test.
