# Prompt para Claude: actualizar el tablero Jira SGCC (AlumVid)

Copia todo lo que está debajo de la línea en una conversación con Claude que tenga el conector de Jira (Atlassian) autorizado.

---

Eres mi asistente de gestión ágil. Necesito que actualices el proyecto de Jira **SGCC** (tablero 34, sitio `jangov04.atlassian.net`) para que refleje el estado real de nuestro proyecto de titulación. Trabaja con las herramientas de Jira disponibles y sigue estas reglas:

## Reglas de trabajo

1. **Primero lee, después escribe.** Antes de crear algo, lista las épicas, historias y sprints que ya existen en SGCC. Si ya hay un issue equivalente (mismo ID HU-xx en el resumen o un título muy parecido), actualízalo en lugar de duplicarlo.
2. **Muéstrame el plan antes de ejecutar.** Presenta una tabla con lo que vas a crear, actualizar o mover (épicas, historias, sprints, subtareas) y espera mi confirmación. No borres issues sin preguntarme.
3. Trabaja por lotes (primero épicas, luego sprints, luego historias, luego subtareas) y al final dame un resumen con los enlaces creados y cualquier error.
4. Usa el idioma español en todos los campos. Formato del resumen de cada historia: `HU-xx · <título corto>`.
5. Si un campo no existe en el proyecto (story points, labels, componentes), omítelo e infórmame; no inventes campos.

## Contexto del proyecto

- **Tema:** Plataforma de control y monitoreo en tiempo real para la optimización de inventario muerto y rutas logísticas en una microempresa de vidrios (AlumVid, Quito).
- **Equipo:** 2 estudiantes (Mosquera Rivadeneira Anthonny Jossue y Ortega Vacas Mateo Michael); tutor: Mario Salvador González.
- **Arquitectura:** 7 servicios Java 21 / Spring Boot 3.4 (gateway 8080, usuarios 8081, inventario 8082, logística 8083, retazos 8084, pedidos 8085, ubicaciones 8086) sobre PostgreSQL 16 + PostGIS 3.4; apps Flutter para Windows (administrador) y Android (todos los roles); despliegue objetivo en Railway.
- **Roles:** Administrador (y cuenta maestra), Vendedor, Bodeguero, Chofer.
- **Metodología:** Scrum, sprints de 2 semanas. Sprints 1–9 terminados; 10–12 pendientes.

## 1. Épicas a crear o verificar

| Clave sugerida | Épica | Descripción |
|---|---|---|
| EP-SEG | Seguridad y usuarios | Autenticación JWT, roles, sesiones revocables, auditoría, validación de cédula/RUC. |
| EP-INV | Inventario general | Catálogo, movimientos INGRESO/SALIDA/AJUSTE, stock decimal exacto. |
| EP-PZA | Piezas y retazos | Piezas físicas, cortes con genealogía, priorización de retazos. |
| EP-BOD | Bodega y ubicaciones | Espacios compartidos y traslados sin cambiar stock. |
| EP-PED | Pedidos y clientes | Clientes, pedidos confirmados, reservas 72 h, preparación, entregas parciales, devoluciones. |
| EP-RUT | Rutas y logística | Rutas multi-destino, optimización Greedy + Google Routes, VRSP. |
| EP-POD | Entrega e-PoD | Foto, firma, GPS, auditoría de desviación. |
| EP-MON | Monitoreo en tiempo real | Telemetría WebSocket y mapa de flota. |
| EP-APP | Apps Windows y Android | Módulos por rol, detección del servidor. |
| EP-CAL | Calidad y pruebas | CI, cobertura, rendimiento, seguridad, UAT, ISO/IEC 25010. |
| EP-DEP | Despliegue Railway | Publicación en la nube, variables, respaldos, distribución de apps. |

## 2. Sprints a crear o verificar

Si los sprints ya existen con otros nombres, renómbralos. Pregúntame las fechas de los sprints 10, 11 y 12 antes de iniciarlos; los sprints 1–9 deben quedar **cerrados**.

| Sprint | Nombre | Objetivo | Estado |
|---|---|---|---|
| SGCC Sprint 1 | Cimientos | Docker Compose, PostgreSQL+PostGIS, usuarios con JWT, API Gateway | Cerrado |
| SGCC Sprint 2 | Inventario y retazos (MVP) | Inventario fraccionado y priorización de retazos | Cerrado |
| SGCC Sprint 3 | Logística base | Servicio de logística, asignación a choferes, cierre de despachos | Cerrado |
| SGCC Sprint 4 | Release MVP | Panel con Kanban y simuladores de rol; release v1.0.0-MVP | Cerrado |
| SGCC Sprint 5 | Reestructuración y rutas espaciales | Microservicios Spring Boot 3.4, rutas multi-destino, geocercas PostGIS | Cerrado |
| SGCC Sprint 6 | App móvil y seguridad | App Flutter del chofer; JWT con jti, revocación, clave temporal, auditoría | Cerrado |
| SGCC Sprint 7 | Pedidos, piezas y bodega | Servicios de retazos, pedidos y ubicaciones | Cerrado |
| SGCC Sprint 8 | Optimización y tiempo real | Greedy + Google Routes, respaldo OSRM, VRSP, telemetría WebSocket | Cerrado |
| SGCC Sprint 9 | Integración pedidos–logística y apps por rol | Despacho comercial transaccional, apps Windows/Android por rol, validación Ecuador | Cerrado |
| SGCC Sprint 10 | Pruebas y calidad | CI GitHub Actions, JaCoCo, E2E, k6, OWASP ZAP, foto solo con cámara | Futuro |
| SGCC Sprint 11 | Despliegue en Railway | Plataforma en producción y apps apuntando a la URL pública | Futuro |
| SGCC Sprint 12 | UAT, evaluación y cierre | UAT, prueba de campo, ISO/IEC 25010, LOPDP, documento final, sustentación | Futuro |

## 3. Historias de usuario

Para cada historia: tipo **Historia**, épica indicada, sprint indicado (si dice "S2/S7", asígnala al último sprint y menciona el primero en la descripción), prioridad (Alta → High, Media → Medium), estado (**Hecho** → Done; **Pendiente** → To Do) y descripción con el formato:

```
Como <rol>, quiero <acción> para <beneficio>.

Criterios de aceptación:
- Dado ... cuando ... entonces ...
Requisito: RF-xx / RNF-xx
```

| ID | Épica | Prioridad | Sprint | Estado | Historia | Criterios de aceptación | Req. |
|---|---|---|---|---|---|---|---|
| HU-01 | EP-INV | Alta | S2 | Hecho | Como Administrador, quiero registrar productos y recepciones de compra para mantener el stock actualizado. | El producto se crea con stock 0; una entrada con motivo suma la cantidad; el historial guarda saldo anterior y posterior. | RF-02 |
| HU-02 | EP-PZA | Alta | S2 | Hecho | Como Bodeguero, quiero registrar las medidas de un retazo sobrante tras un corte para reingresarlo con su pieza de origen. | Dado vidrio 183×244 cm, al cortar 3 cm de ancho con 0,3 cm de merma se crea un retazo de 179,7×244 cm con parentId; un corte que cambia el alto o excede el ancho responde 400 sin cambios. | RF-03 |
| HU-03 | EP-PZA | Alta | S2/S7 | Hecho | Como Vendedor, quiero que el sistema sugiera y reserve retazos compatibles antes que material completo para minimizar el desperdicio. | Las sugerencias se ordenan por menor tamaño suficiente; cortar una pieza completa se rechaza si existe un retazo apto. | RF-04 |
| HU-04 | EP-RUT | Media | S3/S5 | Hecho | Como Administrador, quiero crear rutas con varios pedidos y asignarlas a un chofer disponible para organizar las entregas del día. | Solo se listan choferes activos sin ruta en curso; la ruta queda PENDIENTE con sus paradas. | RF-08 |
| HU-05 | EP-POD | Media | S3/S6 | Hecho | Como Chofer, quiero capturar foto y firma del cliente desde la app para generar la prueba de entrega. | Sin foto o sin firma el botón de entrega no envía; con ambas la parada queda ENTREGADA. | RF-09 |
| HU-06 | EP-POD | Media | S5 | Hecho | Como Administrador, quiero que se guarden las coordenadas GPS de la entrega y su desviación para auditar al chofer. | La desviación se calcula con PostGIS; > 150 m marca alerta. | RF-10 |
| HU-07 | EP-SEG | Alta | S1/S6 | Hecho | Como Administrador, quiero gestionar los accesos del personal por roles para proteger la información. | Un rol sin permiso recibe 403; los permisos se validan en backend. | RF-01, RNF-01 |
| HU-08 | EP-SEG | Alta | S6 | Hecho | Como usuario nuevo, quiero cambiar mi contraseña temporal en el primer ingreso para que solo yo conozca mi clave. | Con clave temporal solo se permite cambiarla; al cambiarla se revocan las sesiones previas. | RF-01 |
| HU-09 | EP-SEG | Alta | S6 | Hecho | Como Administrador, quiero revisar la auditoría de seguridad (incluidos accesos fallidos) para detectar usos indebidos. | Los intentos fallidos y cambios de usuarios aparecen con fecha y actor. | RF-01 |
| HU-10 | EP-SEG | Media | S9 | Hecho | Como cuenta maestra, quiero gestionar a otros administradores para delegar sin perder el control. | Un administrador no maestro no puede editar ni crear administradores. | RF-01 |
| HU-11 | EP-SEG | Media | S9 | Hecho | Como Administrador, quiero que cédula, RUC y teléfono se validen con las reglas de Ecuador para evitar datos erróneos. | Dígito verificador inválido se rechaza en servidor y en las apps. | RF-01 |
| HU-12 | EP-INV | Alta | S2 | Hecho | Como Administrador, quiero ajustar el stock por conteo físico con motivo para corregir diferencias auditables. | El ajuste recibe el total contado y registra el delta; sin diferencia se rechaza. | RF-02 |
| HU-13 | EP-PZA | Media | S7 | Hecho | Como Administrador, quiero desglosar el stock existente en piezas sin volver a sumarlo para catalogar el material que ya tengo. | El modo EXISTENTE no incrementa stock y no supera el saldo sin desglosar. | RF-03 |
| HU-14 | EP-PZA | Media | S7 | Hecho | Como Bodeguero, quiero descartar una pieza dañada conservando su historial para mantener el inventario real. | La pieza queda DESCARTADA con motivo y el stock baja. | RF-03 |
| HU-15 | EP-PZA | Media | S9 | Hecho | Como Vendedor, quiero ver la ficha de una pieza (medidas, ubicación, origen y pedido que la reserva) para responder al cliente. | La ficha muestra genealogía y reserva actual. | RF-03 |
| HU-16 | EP-BOD | Media | S7 | Hecho | Como Administrador, quiero crear espacios de bodega compartidos (A3, B3) para saber dónde está cada material. | Un espacio admite varios productos; no se desactiva si está ocupado. | RF-05 |
| HU-17 | EP-BOD | Media | S7/S9 | Hecho | Como Bodeguero, quiero trasladar cantidades o piezas entre espacios, incluso en masa, sin alterar el stock. | Tras el traslado el stock total no cambia y queda historial. | RF-05 |
| HU-18 | EP-PED | Alta | S7 | Hecho | Como Vendedor, quiero gestionar el catálogo de clientes para asociar cada pedido a un cliente real. | Clientes se crean, editan y desactivan sin borrarse. | RF-06 |
| HU-19 | EP-PED | Alta | S7 | Hecho | Como Vendedor, quiero consultar disponibilidad sin crear un pedido para responder cotizaciones. | La consulta no crea reservas ni movimientos. | RF-06 |
| HU-20 | EP-PED | Alta | S7 | Hecho | Como Vendedor, quiero registrar un pedido confirmado que reserve el material por 72 horas para asegurar la venta. | Faltantes quedan en PENDIENTE_MATERIAL; al vencer se liberan reservas. | RF-06 |
| HU-21 | EP-PED | Alta | S7/S9 | Hecho | Como Bodeguero, quiero preparar el pedido total o parcialmente y que el inventario se descuente solo para no registrar salidas a mano. | Preparar descuenta consumo y merma y crea piezas PREPARADO; repetir el requestId no descuenta de nuevo. | RF-07 |
| HU-22 | EP-PED | Alta | S7 | Hecho | Como Bodeguero, quiero registrar retiros parciales en local para entregar lo que el cliente se lleva. | Cada retiro parcial reinicia 72 h para lo pendiente. | RF-07 |
| HU-23 | EP-PED | Media | S7 | Hecho | Como Vendedor, quiero registrar retrasos y cancelaciones con motivo para que el material se libere o devuelva correctamente. | Cancelar devuelve lo preparado en bodega con sus medidas reales; lo entregado no vuelve. | RF-06, RF-07 |
| HU-24 | EP-PED | Media | S9 | Hecho | Como Bodeguero, quiero recibir físicamente el material de un reparto cancelado para reingresarlo con sus medidas reales. | receive-return es idempotente y solo devuelve esa cantidad. | RF-07 |
| HU-25 | EP-RUT | Alta | S9 | Hecho | Como Administrador, quiero que los pedidos a domicilio listos aparezcan en "Por asignar" para no olvidar ninguno. | Al registrar un pedido a domicilio aparece en Por asignar como "En preparación". | RF-08 |
| HU-26 | EP-RUT | Alta | S8 | Hecho | Como Administrador, quiero que las paradas se ordenen por tiempo real de conducción para reducir tiempo y riesgo de rotura del vidrio. | Orden Greedy con Google Routes; si falla usa OSRM y luego geodesia. | RF-08, RNF-05 |
| HU-27 | EP-RUT | Media | S9 | Hecho | Como Administrador, quiero modificar la carga, quitar paradas o cambiar el chofer de una ruta pendiente para ajustar la planificación. | En una ruta iniciada no se puede cambiar el chofer. | RF-08 |
| HU-28 | EP-RUT | Media | S8 | Hecho | Como Chofer, quiero marcar una parada como no entregada y que la ruta se re-optimice desde mi posición. | Las paradas cerradas conservan su orden; las pendientes se reordenan. | RF-08 |
| HU-29 | EP-MON | Media | S8 | Hecho | Como Administrador, quiero ver en el mapa la posición de los choferes en ruta para dar seguimiento en tiempo real. | La posición se actualiza por WebSocket durante rutas activas. | RF-11 |
| HU-30 | EP-APP | Media | S9 | Hecho | Como usuario de Windows o Android, quiero ver solo los módulos de mi rol para trabajar sin confusiones. | El chofer entra directo a "Mis rutas"; el vendedor no ve Usuarios. | RF-12 |
| HU-31 | EP-APP | Media | S9 | Hecho | Como Chofer, quiero que la app encuentre el servidor en la red para conectarme sin configurar IPs. | "Buscar automáticamente" encuentra el gateway en la misma Wi-Fi. | RF-12 |
| HU-32 | EP-CAL | Alta | S10 | Pendiente | Como equipo, queremos un pipeline de integración continua que compile y pruebe cada cambio para evitar regresiones. | Cada PR ejecuta Maven + pruebas y flutter analyze/test; la rama main está protegida. | RNF-06 |
| HU-33 | EP-CAL | Alta | S10 | Pendiente | Como equipo, queremos pruebas de rendimiento, seguridad y extremo a extremo para verificar los RNF. | p95 < 500 ms con 20 usuarios; sin vulnerabilidades altas en ZAP; cobertura ≥ 70%. | RNF-01, RNF-04, RNF-06 |
| HU-34 | EP-DEP | Alta | S11 | Pendiente | Como Administrador, quiero acceder al sistema publicado en Railway desde cualquier red para operar fuera de la oficina. | Los 8 servicios pasan su healthcheck; el smoke test pasa contra la URL pública; las apps se conectan a ella. | RNF-07 |
| HU-35 | EP-CAL | Alta | S12 | Pendiente | Como Bodeguero y Chofer, queremos validar el sistema en la operación real (UAT) para confirmar que se ajusta a nuestro trabajo. | Casos críticos aprobados por usuarios; SUS ≥ 70; ≤ 4 interacciones por tarea. | RNF-03 |
| HU-36 | EP-POD | Media | S10 | Pendiente | Como Administrador, quiero que la foto de evidencia solo pueda tomarse con la cámara en vivo para evitar evidencias falsas. | La opción "Elegir de galería" desaparece de la pantalla e-PoD. | RF-09 |

## 4. Subtareas para los sprints pendientes

Crea estas subtareas (tipo **Subtarea**) dentro de la historia indicada, en estado To Do:

**HU-32 (S10):** configurar workflow de GitHub Actions para Maven con Testcontainers · agregar flutter analyze y flutter test de ambas apps · proteger ramas main y develop.

**HU-33 (S10):** integrar JaCoCo y publicar el reporte · escribir script k6 para catálogo, piezas y pedidos · medir el Greedy con 30 paradas · ejecutar OWASP ZAP contra el gateway y corregir hallazgos altos · documentar resultados en la memoria (sección 7.3).

**HU-36 (S10):** quitar la opción de galería en `epod_screen.dart` · prueba de widget que verifique que solo existe la opción de cámara.

**HU-34 (S11):** crear el proyecto en Railway y conectar el repositorio · desplegar PostgreSQL/PostGIS con volumen · configurar variables de `deploy/railway/.env.example` en cada servicio · desplegar los 6 servicios privados y el gateway público · limitar memoria JVM (-Xmx) · configurar respaldo pg_dump y probar la restauración · restringir la clave de Google Maps · ejecutar smoke-platform y test-pedidos-logistica contra la URL pública · compilar APK y administrador de Windows con la URL pública · redactar el manual de despliegue.

**HU-35 (S12):** preparar guiones UAT por rol · capacitar al personal · ejecutar la prueba de campo con GPS y cámara reales · aplicar el cuestionario SUS · firmar actas UAT · evaluar ISO/IEC 25010:2023 · revisión LOPDP · actualizar la memoria final (resultados y conclusiones) · preparar la presentación y la sustentación.

## 5. Al terminar

Devuélveme: (a) una tabla de épicas, sprints e historias con su clave de Jira y su enlace; (b) lo que no pudiste crear y por qué; (c) los campos que faltaban en el proyecto.
