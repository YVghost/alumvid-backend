# Prompt para actualizar el tablero Jira: Alum Vid Develop (SGCC)

Copia todo lo que está debajo de la línea en una conversación con el conector de Jira (Atlassian) autorizado o úsalo como guía de asignación en **Alum Vid Develop (SGCC)**.

---

Eres mi asistente de gestión ágil. Necesito que actualices el espacio de Jira **Alum Vid Develop** (proyecto **SGCC**, tablero 34, sitio `jangov04.atlassian.net`) para que refleje el estado real de nuestro proyecto de titulación, incluyendo la **asignación equitativa 50/50 (38 y 38 actividades)** entre los dos integrantes del equipo y el cierre de las épicas completadas. Trabaja con las herramientas de Jira disponibles y sigue estas reglas:

## Reglas de trabajo

1. **Primero lee, después escribe.** Antes de crear algo, lista las épicas, historias, subtareas y sprints que ya existen en **Alum Vid Develop (SGCC)**. Si ya hay un issue equivalente (mismo ID `HU-xx` en el resumen o un título muy parecido), actualízalo en lugar de duplicarlo.
2. **Muéstrame el plan antes de ejecutar.** Presenta una tabla con lo que vas a crear, actualizar o mover (épicas, historias, sprints, subtareas y responsable asignado) y espera mi confirmación. No borres issues sin preguntarme.
3. **Asignación obligatoria de responsable (Assignee):** Ninguna de las **76 actividades** (11 épicas + 36 historias + 29 subtareas) debe quedar *"Sin asignar"*. Asigna cada ítem exactamente al miembro indicado en las tablas (`Anthonny Mosquera` o `Mateo Ortega`), cumpliendo la distribución 50/50 (38 actividades para Anthonny Mosquera y 38 actividades para Mateo Ortega).
4. **Cierre de Épicas completadas:** Las 7 épicas cuyas historias están 100% en estado `Hecho` (`EP-SEG`, `EP-INV`, `EP-PZA`, `EP-BOD`, `EP-RUT`, `EP-MON`, `EP-APP`) deben pasar al estado **Done / Finalizado**.
5. Trabaja por lotes (primero épicas, luego sprints con sus fechas, luego historias, luego subtareas) y al final dame un resumen con los enlaces actualizados y cualquier error.
6. Usa el idioma español en todos los campos. Formato del resumen de cada historia: `HU-xx · <título corto>`.

## Contexto del proyecto

- **Espacio / Proyecto en Jira:** `Alum Vid Develop` (`SGCC`).
- **Tema:** Plataforma de control y monitoreo en tiempo real para la optimización de inventario muerto y rutas logísticas en una microempresa de vidrios (AlumVid, Quito).
- **Equipo (corresponsabilidad 50/50):**
  - **Anthonny Jossue Mosquera Rivadeneira** (38 actividades asignadas: 6 épicas, 18 historias de usuario, 14 subtareas).
  - **Mateo Michael Ortega Vacas** (38 actividades asignadas: 5 épicas, 18 historias de usuario, 15 subtareas).
  - **Docente Guía:** Ing. Mario Salvador González Rodríguez.
- **Arquitectura:** 7 servicios Java 21 / Spring Boot 3.4 (`gateway` 8080, `usuarios` 8081, `inventario` 8082, `logistica` 8083, `retazos` 8084, `pedidos` 8085, `ubicaciones` 8086) sobre PostgreSQL 16 + PostGIS 3.4; apps Flutter para Windows (administrador) y Android (todos los roles); despliegue objetivo en Railway.
- **Roles:** Administrador (y cuenta maestra), Vendedor, Bodeguero, Chofer.
- **Metodología:** Scrum, sprints de 2 semanas. Sprints 1–9 terminados; Sprints 10–12 planificados.

## 1. Épicas a crear o actualizar (11 Épicas)

| Clave sugerida | Épica | Estado | Responsable (Assignee) | Descripción |
|---|---|---|---|---|
| EP-SEG | Seguridad y usuarios | Hecho (Done) | Anthonny Mosquera | Autenticación JWT, roles, sesiones revocables, auditoría, validación de cédula/RUC. |
| EP-INV | Inventario general | Hecho (Done) | Mateo Ortega | Catálogo, movimientos INGRESO/SALIDA/AJUSTE, stock decimal exacto. |
| EP-PZA | Piezas y retazos | Hecho (Done) | Mateo Ortega | Piezas físicas, cortes con genealogía, priorización de retazos. |
| EP-BOD | Bodega y ubicaciones | Hecho (Done) | Mateo Ortega | Espacios compartidos y traslados sin cambiar stock. |
| EP-PED | Pedidos y clientes | En curso (In Progress) | Mateo Ortega | Clientes, pedidos confirmados, reservas 72 h, preparación, entregas parciales, devoluciones. |
| EP-RUT | Rutas y logística | Hecho (Done) | Anthonny Mosquera | Rutas multi-destino, optimización Greedy + Google Routes, VRSP. |
| EP-POD | Entrega e-PoD | En curso (In Progress) | Anthonny Mosquera | Foto, firma, GPS, auditoría de desviación y restricción de cámara en vivo. |
| EP-MON | Monitoreo en tiempo real | Hecho (Done) | Anthonny Mosquera | Telemetría WebSocket y mapa de flota. |
| EP-APP | Apps Windows y Android | Hecho (Done) | Anthonny Mosquera | Módulos por rol, detección del servidor. |
| EP-CAL | Calidad y pruebas | Por hacer (To Do) | Anthonny Mosquera | CI, cobertura, rendimiento, seguridad, UAT, ISO/IEC 25010. |
| EP-DEP | Despliegue Railway | Por hacer (To Do) | Mateo Ortega | Publicación en la nube, variables, respaldos, distribución de apps. |

## 2. Sprints a crear o actualizar con fechas (12 Sprints)

Configura las fechas de inicio y vencimiento en todos los sprints para que ninguna actividad quede sin horizonte temporal. Los Sprints 1–9 deben quedar **Cerrados**.

| Sprint | Fechas | Nombre | Objetivo | Estado |
|---|---|---|---|---|
| SGCC Sprint 1 | 2026-07-20 a 2026-08-02 | Cimientos | Docker Compose, PostgreSQL+PostGIS, usuarios con JWT, API Gateway | Cerrado |
| SGCC Sprint 2 | 2026-08-03 a 2026-08-16 | Inventario y retazos (MVP) | Inventario fraccionado y priorización de retazos | Cerrado |
| SGCC Sprint 3 | 2026-08-17 a 2026-08-30 | Logística base | Servicio de logística, asignación a choferes, cierre de despachos | Cerrado |
| SGCC Sprint 4 | 2026-08-31 a 2026-09-13 | Release MVP | Panel con Kanban y simuladores de rol; release v1.0.0-MVP | Cerrado |
| SGCC Sprint 5 | 2026-09-14 a 2026-09-27 | Reestructuración y rutas espaciales | Microservicios Spring Boot 3.4, rutas multi-destino, geocercas PostGIS | Cerrado |
| SGCC Sprint 6 | 2026-09-28 a 2026-10-11 | App móvil y seguridad | App Flutter del chofer; JWT con jti, revocación, clave temporal, auditoría | Cerrado |
| SGCC Sprint 7 | 2026-10-12 a 2026-10-25 | Pedidos, piezas y bodega | Servicios de retazos, pedidos y ubicaciones | Cerrado |
| SGCC Sprint 8 | 2026-10-26 a 2026-11-08 | Optimización y tiempo real | Greedy + Google Routes, respaldo OSRM, VRSP, telemetría WebSocket | Cerrado |
| SGCC Sprint 9 | 2026-11-09 a 2026-11-15 | Integración pedidos–logística y apps por rol | Despacho comercial transaccional, apps Windows/Android por rol, validación Ecuador | Cerrado |
| SGCC Sprint 10 | 2026-11-16 a 2026-11-29 | Pruebas y calidad | CI GitHub Actions, JaCoCo, E2E, k6, OWASP ZAP, foto solo con cámara | Activo / Futuro |
| SGCC Sprint 11 | 2026-11-30 a 2026-12-13 | Despliegue en Railway | Plataforma en producción y apps apuntando a la URL pública | Futuro |
| SGCC Sprint 12 | 2026-12-14 a 2026-12-27 | UAT, evaluación y cierre | UAT, prueba de campo, ISO/IEC 25010, LOPDP, documento final, sustentación | Futuro |

## 3. Historias de usuario (36 Historias: 18 Anthonny Mosquera / 18 Mateo Ortega)

Para cada historia: tipo **Historia**, épica indicada, sprint indicado, prioridad (`Alta` → High, `Media` → Medium), responsable asignado (**Assignee**), puntos de historia (`Story Points`) y estado (**Hecho** → Done; **Pendiente** → To Do).

| ID | Épica | Prioridad | Sprint | Estado | Responsable (Assignee) | Story Points | Historia | Criterios de aceptación | Req. |
|---|---|---|---|---|---|---:|---|---|---|
| HU-01 | EP-INV | Alta | S2 | Hecho | Mateo Ortega | 5 | Como Administrador, quiero registrar productos y recepciones de compra para mantener el stock actualizado. | El producto se crea con stock 0; una entrada con motivo suma la cantidad; el historial guarda saldo anterior y posterior. | RF-02 |
| HU-02 | EP-PZA | Alta | S2 | Hecho | Mateo Ortega | 8 | Como Bodeguero, quiero registrar las medidas de un retazo sobrante tras un corte para reingresarlo con su pieza de origen. | Dado vidrio 183×244 cm, al cortar 3 cm de ancho con 0,3 cm de merma se crea un retazo de 179,7×244 cm con parentId; un corte que cambia el alto o excede el ancho responde 400 sin cambios. | RF-03 |
| HU-03 | EP-PZA | Alta | S2/S7 | Hecho | Mateo Ortega | 8 | Como Vendedor, quiero que el sistema sugiera y reserve retazos compatibles antes que material completo para minimizar el desperdicio. | Las sugerencias se ordenan por menor tamaño suficiente; cortar una pieza completa se rechaza si existe un retazo apto. | RF-04 |
| HU-04 | EP-RUT | Media | S3/S5 | Hecho | Anthonny Mosquera | 8 | Como Administrador, quiero crear rutas con varios pedidos y asignarlas a un chofer disponible para organizar las entregas del día. | Solo se listan choferes activos sin ruta en curso; la ruta queda PENDIENTE con sus paradas. | RF-08 |
| HU-05 | EP-POD | Media | S3/S6 | Hecho | Anthonny Mosquera | 8 | Como Chofer, quiero capturar foto y firma del cliente desde la app para generar la prueba de entrega. | Sin foto o sin firma el botón de entrega no envía; con ambas la parada queda ENTREGADA. | RF-09 |
| HU-06 | EP-POD | Media | S5 | Hecho | Anthonny Mosquera | 5 | Como Administrador, quiero que se guarden las coordenadas GPS de la entrega y su desviación para auditar al chofer. | La desviación se calcula sobre geometrías PostGIS (SRID 4326); > 150 m marca alerta. | RF-10 |
| HU-07 | EP-SEG | Alta | S1/S6 | Hecho | Anthonny Mosquera | 8 | Como Administrador, quiero gestionar los accesos del personal por roles para proteger la información. | Un rol sin permiso recibe 403; los permisos se validan en backend. | RF-01, RNF-01 |
| HU-08 | EP-SEG | Alta | S6 | Hecho | Anthonny Mosquera | 5 | Como usuario nuevo, quiero cambiar mi contraseña temporal en el primer ingreso para que solo yo conozca mi clave. | Con clave temporal solo se permite cambiarla; al cambiarla se revocan las sesiones previas. | RF-01 |
| HU-09 | EP-SEG | Alta | S6 | Hecho | Anthonny Mosquera | 5 | Como Administrador, quiero revisar la auditoría de seguridad (incluidos accesos fallidos) para detectar usos indebidos. | Los intentos fallidos y cambios de usuarios aparecen con fecha y actor. | RF-01 |
| HU-10 | EP-SEG | Media | S9 | Hecho | Mateo Ortega | 5 | Como cuenta maestra, quiero gestionar a otros administradores para delegar sin perder el control. | Un administrador no maestro no puede editar ni crear administradores. | RF-01 |
| HU-11 | EP-SEG | Media | S9 | Hecho | Anthonny Mosquera | 5 | Como Administrador, quiero que cédula, RUC y teléfono se validen con las reglas de Ecuador para evitar datos erróneos. | Dígito verificador inválido se rechaza en servidor y en las apps. | RF-01 |
| HU-12 | EP-INV | Alta | S2 | Hecho | Mateo Ortega | 5 | Como Administrador, quiero ajustar el stock por conteo físico con motivo para corregir diferencias auditables. | El ajuste recibe el total contado y registra el delta; sin diferencia se rechaza. | RF-02 |
| HU-13 | EP-PZA | Media | S7 | Hecho | Mateo Ortega | 5 | Como Administrador, quiero desglosar el stock existente en piezas sin volver a sumarlo para catalogar el material que ya tengo. | El modo EXISTENTE no incrementa stock y no supera el saldo sin desglosar. | RF-03 |
| HU-14 | EP-PZA | Media | S7 | Hecho | Mateo Ortega | 5 | Como Bodeguero, quiero descartar una pieza dañada conservando su historial para mantener el inventario real. | La pieza queda DESCARTADA con motivo y el stock baja. | RF-03 |
| HU-15 | EP-PZA | Media | S9 | Hecho | Mateo Ortega | 3 | Como Vendedor, quiero ver la ficha de una pieza (medidas, ubicación, origen y pedido que la reserva) para responder al cliente. | La ficha muestra genealogía y reserva actual. | RF-03 |
| HU-16 | EP-BOD | Media | S7 | Hecho | Mateo Ortega | 5 | Como Administrador, quiero crear espacios de bodega compartidos (A3, B3) para saber dónde está cada material. | Un espacio admite varios productos; no se desactiva si está ocupado. | RF-05 |
| HU-17 | EP-BOD | Media | S7/S9 | Hecho | Mateo Ortega | 5 | Como Bodeguero, quiero trasladar cantidades o piezas entre espacios, incluso en masa, sin alterar el stock. | Tras el traslado el stock total no cambia y queda historial. | RF-05 |
| HU-18 | EP-PED | Alta | S7 | Hecho | Mateo Ortega | 5 | Como Vendedor, quiero gestionar el catálogo de clientes para asociar cada pedido a un cliente real. | Clientes se crean, editan y desactivan sin borrarse. | RF-06 |
| HU-19 | EP-PED | Alta | S7 | Hecho | Mateo Ortega | 5 | Como Vendedor, quiero consultar disponibilidad sin crear un pedido para responder cotizaciones. | La consulta no crea reservas ni movimientos. | RF-06 |
| HU-20 | EP-PED | Alta | S7 | Hecho | Mateo Ortega | 8 | Como Vendedor, quiero registrar un pedido confirmado que reserve el material por 72 horas para asegurar la venta. | Faltantes quedan en PENDIENTE_MATERIAL; al vencer se liberan reservas. | RF-06 |
| HU-21 | EP-PED | Alta | S7/S9 | Hecho | Mateo Ortega | 8 | Como Bodeguero, quiero preparar el pedido total o parcialmente y que el inventario se descuente solo para no registrar salidas a mano. | Preparar descuenta consumo y merma y crea piezas PREPARADO; repetir el requestId no descuenta de nuevo. | RF-07 |
| HU-22 | EP-PED | Alta | S7 | Hecho | Mateo Ortega | 5 | Como Bodeguero, quiero registrar retiros parciales en local para entregar lo que el cliente se lleva. | Cada retiro parcial reinicia 72 h para lo pendiente. | RF-07 |
| HU-23 | EP-PED | Media | S7 | Hecho | Mateo Ortega | 5 | Como Vendedor, quiero registrar retrasos y cancelaciones con motivo para que el material se libere o devuelva correctamente. | Cancelar devuelve lo preparado en bodega con sus medidas reales; lo entregado no vuelve. | RF-06, RF-07 |
| HU-24 | EP-PED | Media | S9 | Hecho | Anthonny Mosquera | 5 | Como Bodeguero, quiero recibir físicamente el material de un reparto cancelado para reingresarlo con sus medidas reales. | receive-return es idempotente y solo devuelve esa cantidad. | RF-07 |
| HU-25 | EP-RUT | Alta | S9 | Hecho | Anthonny Mosquera | 5 | Como Administrador, quiero que los pedidos a domicilio listos aparezcan en "Por asignar" para no olvidar ninguno. | Al registrar un pedido a domicilio aparece en Por asignar como "En preparación". | RF-08 |
| HU-26 | EP-RUT | Alta | S8 | Hecho | Anthonny Mosquera | 8 | Como Administrador, quiero que las paradas se ordenen por tiempo real de conducción para reducir tiempo y riesgo de rotura del vidrio. | Orden Greedy con Google Routes; si falla usa OSRM y luego geodesia. | RF-08, RNF-05 |
| HU-27 | EP-RUT | Media | S9 | Hecho | Anthonny Mosquera | 5 | Como Administrador, quiero modificar la carga, quitar paradas o cambiar el chofer de una ruta pendiente para ajustar la planificación. | En una ruta iniciada no se puede cambiar el chofer. | RF-08 |
| HU-28 | EP-RUT | Media | S8 | Hecho | Anthonny Mosquera | 8 | Como Chofer, quiero marcar una parada como no entregada y que la ruta se re-optimice desde mi posición. | Las paradas cerradas conservan su orden; las pendientes se reordenan. | RF-08 |
| HU-29 | EP-MON | Media | S8 | Hecho | Anthonny Mosquera | 8 | Como Administrador, quiero ver en el mapa la posición de los choferes en ruta para dar seguimiento en tiempo real. | La posición se actualiza por WebSocket durante rutas activas. | RF-11 |
| HU-30 | EP-APP | Media | S9 | Hecho | Anthonny Mosquera | 5 | Como usuario de Windows o Android, quiero ver solo los módulos de mi rol para trabajar sin confusiones. | El chofer entra directo a "Mis rutas"; el vendedor no ve Usuarios. | RF-12 |
| HU-31 | EP-APP | Media | S9 | Hecho | Anthonny Mosquera | 5 | Como Chofer, quiero que la app encuentre el servidor en la red para conectarme sin configurar IPs. | "Buscar automáticamente" encuentra el gateway en la misma Wi-Fi. | RF-12 |
| HU-32 | EP-CAL | Alta | S10 | Pendiente | Mateo Ortega | 5 | Como equipo, queremos un pipeline de integración continua que compile y pruebe cada cambio para evitar regresiones. | Cada PR ejecuta Maven + pruebas y flutter analyze/test; la rama main está protegida. | RNF-06 |
| HU-33 | EP-CAL | Alta | S10 | Pendiente | Anthonny Mosquera | 8 | Como equipo, queremos pruebas de rendimiento, seguridad y extremo a extremo para verificar los RNF. | p95 < 500 ms con 20 usuarios; sin vulnerabilidades altas en ZAP; cobertura ≥ 70%. | RNF-01, RNF-04, RNF-06 |
| HU-34 | EP-DEP | Alta | S11 | Pendiente | Mateo Ortega | 8 | Como Administrador, quiero acceder al sistema publicado en Railway desde cualquier red para operar fuera de la oficina. | Los 8 servicios pasan su healthcheck; el smoke test pasa contra la URL pública; las apps se conectan a ella. | RNF-07 |
| HU-35 | EP-CAL | Alta | S12 | Pendiente | Anthonny Mosquera | 8 | Como Bodeguero y Chofer, queremos validar el sistema en la operación real (UAT) para confirmar que se ajusta a nuestro trabajo. | Casos críticos aprobados por usuarios; SUS ≥ 70; ≤ 4 interacciones por tarea. | RNF-03 |
| HU-36 | EP-POD | Media | S10 | Pendiente | Anthonny Mosquera | 3 | Como Administrador, quiero que la foto de evidencia solo pueda tomarse con la cámara en vivo para evitar evidencias falsas. | La opción "Elegir de galería" desaparece de la pantalla e-PoD. | RF-09 |

## 4. Subtareas para los sprints pendientes (29 Subtareas: 14 Anthonny Mosquera / 15 Mateo Ortega)

Crea o actualiza estas subtareas (tipo **Subtarea**) dentro de la historia indicada, en estado `To Do`, asignando el responsable correspondiente:

**HU-32 (S10 — 3 subtareas):**
1. Configurar workflow de GitHub Actions para Maven con Testcontainers (`Assignee: Mateo Ortega`).
2. Agregar `flutter analyze` y `flutter test` de ambas apps (`Assignee: Anthonny Mosquera`).
3. Proteger ramas `main` y `develop` (`Assignee: Mateo Ortega`).

**HU-33 (S10 — 5 subtareas):**
4. Integrar JaCoCo y publicar el reporte (`Assignee: Mateo Ortega`).
5. Escribir script k6 para catálogo, piezas y pedidos (`Assignee: Mateo Ortega`).
6. Medir el algoritmo Greedy con 30 paradas (`Assignee: Anthonny Mosquera`).
7. Ejecutar OWASP ZAP contra el gateway y corregir hallazgos altos (`Assignee: Anthonny Mosquera`).
8. Documentar resultados en la memoria (sección 7.3) (`Assignee: Anthonny Mosquera`).

**HU-36 (S10 — 2 subtareas):**
9. Quitar la opción de galería en `epod_screen.dart` (`Assignee: Anthonny Mosquera`).
10. Prueba de widget que verifique que solo existe la opción de cámara (`Assignee: Anthonny Mosquera`).

**HU-34 (S11 — 10 subtareas):**
11. Crear el proyecto en Railway y conectar el repositorio (`Assignee: Mateo Ortega`).
12. Desplegar PostgreSQL/PostGIS con volumen (`Assignee: Mateo Ortega`).
13. Configurar variables de `deploy/railway/.env.example` en cada servicio (`Assignee: Mateo Ortega`).
14. Desplegar los 6 servicios privados y el gateway público (`Assignee: Mateo Ortega`).
15. Limitar memoria JVM (`-Xmx`) (`Assignee: Mateo Ortega`).
16. Configurar respaldo `pg_dump` y probar la restauración (`Assignee: Mateo Ortega`).
17. Restringir la clave de Google Maps (`Assignee: Anthonny Mosquera`).
18. Ejecutar `smoke-platform` y `test-pedidos-logistica` contra la URL pública (`Assignee: Mateo Ortega`).
19. Compilar APK y administrador de Windows con la URL pública (`Assignee: Anthonny Mosquera`).
20. Redactar el manual de despliegue (`Assignee: Mateo Ortega`).

**HU-35 (S12 — 9 subtareas):**
21. Preparar guiones UAT por rol (`Assignee: Anthonny Mosquera`).
22. Capacitar al personal (`Assignee: Mateo Ortega`).
23. Ejecutar la prueba de campo con GPS y cámara reales (`Assignee: Anthonny Mosquera`).
24. Aplicar el cuestionario SUS (`Assignee: Anthonny Mosquera`).
25. Firmar actas UAT (`Assignee: Mateo Ortega`).
26. Evaluar ISO/IEC 25010:2023 (`Assignee: Mateo Ortega`).
27. Revisión LOPDP (`Assignee: Anthonny Mosquera`).
28. Actualizar la memoria final (resultados y conclusiones) (`Assignee: Anthonny Mosquera`).
29. Preparar la presentación y la sustentación (`Assignee: Anthonny Mosquera`).

## 5. Resumen de distribución equitativa (Total: 76 actividades)

| Tipo de Actividad | Anthonny Mosquera | Mateo Ortega | Total |
|---|---:|---:|---:|
| Épicas | 6 | 5 | 11 |
| Historias de Usuario | 18 | 18 | 36 |
| Subtareas | 14 | 15 | 29 |
| **Total Asignado** | **38 (50%)** | **38 (50%)** | **76 (100%)** |

## 6. Al terminar

Devuélveme: (a) una tabla de épicas, sprints, historias y subtareas con su clave de Jira, responsable y enlace; (b) confirmación de que existen **0 actividades sin asignar** en el proyecto; (c) confirmación de que las 7 épicas completadas aparecen en estado `Done`.
