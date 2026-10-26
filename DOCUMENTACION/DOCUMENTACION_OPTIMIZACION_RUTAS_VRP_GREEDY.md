# Documentación Técnica: Optimización de Rutas Logísticas en AlumVid
## De la Teoría del Vehicle Routing Problem (VRP) a la Heurística Voraz (Greedy Search) con Google Routes API y Re-enrutado Dinámico (VRSP)

**Institución:** Universidad de Las Américas (UDLA)  
**Facultad:** Facultad de Ingeniería y Ciencias Aplicadas – Carrera de Ingeniería de Software  
**Proyecto de Titulación:** Plataforma de control y monitoreo en tiempo real para la optimización de inventario muerto y rutas logísticas en una microempresa de vidrios (AlumVid)  
**Estudiantes:** Anthonny Jossue Mosquera Rivadeneira, Mateo Michael Ortega Vacas  
**Tutor Guía:** Prof. Mario Salvador González Rodríguez  
**Ubicación de la Bodega Central:** Arq-AlumVid (Coordenadas: Latitud -0.089290, Longitud -78.439607, Sector Calderón / Llano Grande, Quito Norte)  
**Fecha:** Octubre 2026 – Quito, Ecuador  

---

## 1. Contexto y Objetivos del Requerimiento

Durante la sesión de seguimiento y asesoría del proyecto de titulación con el tutor guía Prof. Mario Salvador González Rodríguez, se identificó la necesidad imperativa de elevar el rigor técnico, científico y operativo del subsistema de distribución logística de AlumVid. 

El tutor instruyó articular las siguientes directrices en la ingeniería del software y en el marco conceptual de la memoria técnica:

1. **Greedy Search + Driving Distance (Google Routes API):** Reemplazar cualquier cálculo simplificado de distancias en línea recta por distancias y tiempos reales de conducción vehicular sobre la malla vial urbana, obtenidos mediante servicios cartográficos de alto nivel.
2. **El Modelo Ideal: Vehicle Routing Problem (VRP):** Formalizar y contrastar la solución algorítmica adoptada contra el modelo teórico ideal del problema de enrutamiento de vehículos con flota finita y capacidad restringida (CVRP), justificando con solidez académica por qué dicho modelo exacto se adapta a la realidad de una microempresa ecuatoriana.
3. **Vehicle Rescheduling Problem (VRSP):** Dotar a la plataforma de reactividad dinámica en tiempo real para reordenar de manera automática el itinerario de paradas pendientes cuando surjan imprevistos viales o cancelaciones de entregas en campo.
4. **Articulación con la Investigación Científica de Siniestralidad Vial en Quito:** Incorporar los hallazgos del artículo científico coautorado por el tutor sobre la accidentalidad y el tráfico en el Distrito Metropolitano de Quito (*Urban Science*, 2026), vinculando la optimización por tiempo de traslado con la preservación física de la carga frágil de vidrio plano.

---

## 2. Diagnóstico Crítico: ¿Por qué la Solución Anterior era Ineficiente?

Antes de implementar las directrices del tutor, el sistema calculaba el orden de despacho de los pedidos mediante una aproximación geométrica básica basada en la fórmula geodésica de Haversine. Aunque este método es común en prototipos de software elementales, en el entorno logístico real de Quito provocaba graves ineficiencias operativas y financieras:

### 2.1. La Falacia del "Vuelo de Pájaro" (Distancia en Línea Recta)
La fórmula de Haversine calcula la distancia de círculo máximo sobre la curvatura de una esfera ideal, asumiendo que los camiones de reparto se desplazan por el aire sin obstáculos físicos. En una ciudad montañosa como Quito, esta suposición es completamente falsa. Dos clientes pueden estar a escasos 900 metros en línea recta, pero físicamente separados por una quebrada natural o una falla geográfica (como la quebrada de Guápulo o el río Machángara), lo que exige un recorrido vehicular real de más de 5 a 7 kilómetros por avenidas perimetrales.

### 2.2. Desconocimiento de la Red Vial y el Sentido Único de las Calles
El cálculo geométrico plano asume simetría absoluta: considera que la distancia de ida desde el punto A hacia el punto B es idéntica a la distancia de retorno de B hacia A. En la realidad urbana de Quito, la red vial es profundamente asimétrica debido a la existencia de corredores troncales unidireccionales (tales como la Av. Amazonas, Av. 10 de Agosto, Av. 6 de Diciembre y Av. Galo Plaza Lasso), pasos a desnivel, redondeles y giros prohibidos a la izquierda. Un camión que viaja de sur a norte utiliza rutas distintas y recorre distancias muy diferentes a las que emplea en sentido norte a sur.

### 2.3. Ceguera ante el Tráfico y los Tiempos Reales de Traslado
La solución anterior medía proximidad únicamente en kilómetros lineales, sin considerar el tiempo de viaje ni la congestión vehicular. En la logística urbana moderna, **un kilómetro no equivale a un tiempo fijo**:
* Un tramo de 4 kilómetros sobre una vía rápida perimetral (como la Av. Simón Bolívar) puede completarse en apenas 5 minutos con flujo continuo.
* Un tramo de apenas 1.5 kilómetros en el hipercentro urbano (como Iñaquito o La Mariscal) en horas de alta demanda puede tomar 25 minutos debido a semáforos continuos, congestión e intersecciones saturadas.
Al minimizar distancias planas en lugar de tiempos de conducción, el sistema anterior enviaba frecuentemente a los camiones a atravesar cuellos de botella de alto tráfico, incrementando el consumo de combustible, el desgaste mecánico y el retraso en las entregas.

### 2.4. Rutas Rígidas e Inflexibles
Si durante el transcurso del día un cliente rechazaba un pedido, no se encontraba en la obra o una vía colapsaba por un siniestro de tránsito, el chofer se veía obligado a continuar con una lista estática predeterminada por la mañana. Esto ocasionaba trayectos erráticos, retornos innecesarios a sectores ya transitados y pérdidas de horas laborales.

### 2.5. Alto Riesgo de Rotura para Cargas Frágiles de Vidrio
El transporte de vidrio arquitectónico y perfiles de aluminio exige condiciones de manejo suaves y estables. El vidrio es susceptible a fisuras y roturas catastróficas cuando el vehículo experimenta frenazos intempestivos, baches pronunciados, pendientes extremas o maniobras de detención y arranque continuo provocadas por el tráfico denso. Enviar camiones cargados de vidrio por rutas lentas y congestionadas aumentaba exponencialmente el índice de merma por rotura de producto.

---

## 3. La Bodega Central de AlumVid y su Relevancia Operativa

La Bodega Central de la empresa opera bajo la denominación técnica **Arq-AlumVid**, ubicada en las coordenadas geográficas exactas:

* **Latitud:** `-0.089290`
* **Longitud:** `-78.439607`
* **Ubicación Urbana:** Sector Calderón / Llano Grande / Carapungo, extremo norte del Distrito Metropolitano de Quito.

### Implicaciones Logísticas de la Ubicación en el Extremo Norte
Estar situado en el extremo norte de la urbe impone desafíos logísticos específicos que justifican plenamente el uso de la API vial de Google:
1. **Acceso Obligatorio por Corredores Troncales:** Cualquier despacho que deba abastecer obras en el centro comercial de Quito (La Carolina, Iñaquito), en los valles orientales (Cumbayá, Tumbaco) o en el sur (El Recreo, Quitumbe) debe atravesar corredores de alta circulación vehicular como la Panamericana Norte, la Autopista Simón Bolívar o la Av. Galo Plaza Lasso.
2. **Alta Sensibilidad al Sentido de Flujo:** Durante las mañanas, el flujo norte-sur hacia el centro de Quito experimenta alta congestión; en las tardes ocurre el fenómeno inverso. Una medición basada en tiempo real de conducción permite que el despachador programe las salidas en las franjas horarias y sentidos viales más convenientes.
3. **Costo de Retorno al Depósito:** Dado que los camiones deben retornar a Calderón al finalizar las entregas, la última parada del itinerario debe planificarse estratégicamente para minimizar el tiempo de retorno a la bodega Arq-AlumVid.

---

## 4. Fundamentación Teórica del Modelo Ideal: Vehicle Routing Problem (VRP)

El **Problema de Enrutamiento de Vehículos (Vehicle Routing Problem - VRP)** es uno de los problemas fundamentales más estudiados de la optimización combinatoria y la investigación operativa. Formulado originalmente por Dantzig y Ramser en 1959, modela la distribución óptima de bienes desde un depósito central hacia múltiples clientes mediante una flota de vehículos de transporte.

### 4.1. Componentes del Modelo Aplicados a AlumVid
* **Depósito Central (Bodega Arq-AlumVid):** Punto geográfico fijo (coordenadas -0.089290, -78.439607) donde se almacenan las láminas de vidrio, perfiles de aluminio y herrajes, desde donde inician y adonde concluyen todos los recorridos vehiculares.
* **Conjunto de Destinos (Obras y Clientes):** Puntos de entrega distribuidos en la geografía urbana, cada uno con una demanda específica de volumen y peso.
* **Flota de Vehículos de Entrega:** Conjunto finito de camiones o camionetas de la empresa, cada uno con un chofer asignado y una capacidad de carga limitada.
* **Costo de Tránsito Vial:** Esfuerzo o penalización requerida para desplazarse entre cualquier par de paradas. En la implementación de AlumVid, este costo corresponde al **tiempo real de conducción en minutos/segundos**, obtenido a través de Google Routes API.

### 4.2. Las Cinco Reglas Obligatorias del Modelo VRP
Para que una solución de enrutamiento sea matemáticamente válida y aplicable en la realidad, el modelo impone cinco restricciones fundamentales expresadas en lenguaje natural:

1. **Regla de Entrega Única:** Cada cliente u obra debe ser visitado exactamente una sola vez por un único camión asignado. Ninguna entrega puede quedar sin atender ni repetirse.
2. **Regla de Salida y Retorno a Bodega:** Todo camión de reparto debe comenzar su jornada obligatoriamente saliendo desde la Bodega Central Arq-AlumVid y, tras entregar el último pedido, debe retornar a la misma bodega central.
3. **Regla de Conservación de Flujo:** Si un vehículo arriba al punto de entrega de un cliente, debe salir de manera obligatoria de ese punto hacia el siguiente cliente planificado o de vuelta a la bodega, impidiendo que el trayecto quede inconcluso.
4. **Regla de Capacidad Máxima de Carga (Capacitated VRP - CVRP):** La sumatoria del peso y volumen de todos los pedidos asignados a un camión jamás debe superar la capacidad de carga nominal de dicho vehículo, evitando sobrecargas estructurales que pongan en peligro el vidrio transportado.
5. **Regla de Eliminación de Circuitos Aislados:** No se permite que existan grupos de paradas conectadas entre sí formando bucles cerrados que no tengan conexión con la Bodega Central Arq-AlumVid.

### 4.3. Justificación Técnica: ¿Por qué el VRP Exacto no se Ejecuta en Tiempo Real en una PYME?
Resolver el modelo VRP exacto de manera determinista es un problema clasificado formalmente como **NP-Hard**. Esto implica que:

* **Explosión Combinatoria Factorial:** El número de permutaciones posibles crece a un ritmo factorial con respecto al número de paradas. Para 10 paradas existen más de 3.6 millones de rutas posibles; para 15 paradas, las combinaciones superan los 1.3 billones; y para 25 paradas, el número de posibilidades excede la cantidad de átomos en el planeta Tierra.
* **Tiempos de Procesamiento Incompatibles:** Hallar la solución matemática exacta requiere algoritmos pesados de programación lineal entera mixta y métodos de bifurcación y acotación (Branch and Cut) que tardan desde minutos hasta varias horas en un servidor empresarial. Esto es inaceptable para una aplicación móvil donde el chofer o el despachador requieren respuestas en menos de 200 milisegundos.
* **Costos Prohibitivos de Servicios en la Nube:** Proveedores comerciales como Google Cloud Fleet Engine o Google Route Optimization API cobran tarifas considerables por cada cálculo de optimización de flota completa, lo que resulta inviable financieramente para una microempresa ecuatoriana.
* **Dinámica Operativa Real de AlumVid:** En la práctica diaria de AlumVid, el despachador humano ya conoce las prioridades de sus clientes, la disponibilidad de los camiones y el tipo de vidrio a enviar. Por consiguiente, la necesidad primordial del software no es reemplazar el criterio del despachador en la asignación de flotas, sino **ordenar la secuencia de paradas de cada camión con la máxima velocidad, mínimo costo y exactitud vial**.

---

## 5. La Solución Implementada: Greedy Search Guiada por Tiempo Real de Conducción

Para cumplir con la directriz del tutor ("Greedy Search + driving distance Google API"), el equipo de desarrollo implementó la **Heurística Voraz del Vecino Más Cercano (Nearest Neighbor Heuristic)** sustituyendo la distancia euclidiana por el tiempo real de manejo en tráfico urbano.

### 5.1. Funcionamiento del Algoritmo Paso a Paso
El algoritmo opera de forma iterativa y secuencial:

1. **Definición del Punto de Origen:** El algoritmo toma como punto inicial la ubicación de la Bodega Central Arq-AlumVid (o la ubicación GPS actual del chofer si la ruta ya está en progreso).
2. **Consulta de la Matriz Vial:** Se consulta la matriz vial calculada por Google Routes API para conocer el tiempo de conducción en segundos desde el origen hacia cada uno de los clientes pendientes.
3. **Selección Voraz Inmediata:** El algoritmo examina todas las opciones y escoge inmediatamente aquel cliente que presente el **menor tiempo de conducción en minutos**.
4. **Actualización de Estado:** El cliente seleccionado se marca como visitado y se añade a la secuencia ordenada de la ruta.
5. **Iteración Secuencial:** El punto recién seleccionado se convierte en el nuevo punto de partida. Se repite el procedimiento evaluando únicamente a los clientes que aún quedan pendientes.
6. **Finalización del Itinerario:** El ciclo se detiene cuando la totalidad de los destinos han sido ordenados.

### 5.2. Ventajas Técnicas de la Heurística Voraz
* **Velocidad de Respuesta Instantánea:** Presenta una complejidad temporal cuadrática $O(N^2)$, resolviendo secuencias de 15 a 30 paradas en menos de 100 milisegundos en el backend Spring Boot.
* **Reducción Efectiva de Costos de API:** Se solicita una única matriz de distancias por lote (batch matrix request), lo que optimiza el consumo de la cuota de la API de Google Maps Platform.
* **Alineación con la Filosofía Voraz:** Al tomar en cada parada la decisión localmente óptima (ir al cliente más cercano en tiempo), la ruta global resultante es altamente eficiente y evita trayectos innecesarios por la ciudad.

---

## 6. Re-enrutado Dinámico ante Contingencias (Vehicle Rescheduling Problem - VRSP)

En la distribución urbana real, las contingencias en ruta son inevitables. El **Problema de Re-planificación de Vehículos (Vehicle Rescheduling Problem - VRSP)** modela la capacidad de ajustar y recalcular la ruta mientras el vehículo se encuentra en pleno tránsito.

### Escenarios de Contingencia Frecuentes en AlumVid:
* El cliente no tiene lista la obra para descargar las hojas de vidrio templado.
* El chofer no encuentra a la persona autorizada para firmar el acta de entrega.
* Ocurre un bloqueo vial, accidente o manifestación que imposibilita el paso hacia una dirección.
* El despachador cancela o reprograma un pedido de emergencia desde el panel administrativo.

### Mecanismo de Re-enrutado Automático en AlumVid:
1. **Preservación Estricta del Registro Histórico:** Las paradas que ya fueron entregadas con su comprobante electrónico (e-PoD con foto y firma digital) o que fueron marcadas como canceladas conservan intacto su índice y marca temporal original para garantizar la integridad contable y legal de las operaciones.
2. **Captura de la Ubicación GPS en Vivo:** Al reportarse la cancelación o el estado "No entregado", el sistema captura las coordenadas GPS exactas en donde se encuentra el camión en ese momento.
3. **Re-optimización Exclusiva de Paradas Pendientes:** El backend toma la posición GPS actual del camión como nuevo punto de partida y ejecuta la búsqueda voraz únicamente sobre las entregas que siguen pendientes.
4. **Sincronización Inmediata en Dispositivos:** Mediante conexiones seguras y WebSockets, la aplicación móvil del chofer redibuja de inmediato su itinerario destacando el nuevo destino prioritario, y la aplicación de escritorio del administrador actualiza el mapa interactivo sin requerir recargar la página.

---

## 7. Arquitectura de Resiliencia en Tres Niveles

Para garantizar que la microempresa AlumVid nunca detenga sus despachos por fallas externas de conectividad o límites de facturación en Google Cloud, se implementó en `GoogleRoutesService.java` un patrón de diseño desacoplado y tolerante a fallos estructurado en tres niveles jerárquicos:

| Nivel de Resiliencia | Proveedor / Tecnología | Ventaja Operativa | Condición de Activación |
| :--- | :--- | :--- | :--- |
| **Nivel 1 (Primario)** | **Google Routes API v2 (`computeRouteMatrix`)** | Máxima precisión vial, considera tráfico en tiempo real, sentidos de calles y giros prohibidos en Quito. | Operación normal con API Key activa y conexión a Internet. |
| **Nivel 2 (Fallback Secundario)** | **OSRM Table Service (Open Source Routing Machine)** | Basado en la malla vial libre de OpenStreetMap. Gratuito, sin límite de cuota y con cálculo de tiempos viales reales. | Falla de red hacia Google, error 403/429 de cuota o clave deshabilitada. |
| **Nivel 3 (Fallback Terciario)** | **Geodesia Calibrada a Velocidad Urbana de Quito** | Cálculo matemático autónomo local con velocidad calibrada a 25 km/h urbanos (6.94 m/s). No requiere red externa. | Caída total de servicios web o pérdida de señal en túneles/zonas rurales. |

---

## 8. Evidencia Empírica de Asimetría Vial en el Distrito Metropolitano de Quito

Para validar la superioridad de Google Routes API frente al cálculo euclídeo, se realizaron pruebas de medición tomando como origen la Bodega Central Arq-AlumVid (coordenadas -0.089290, -78.439607) hacia puntos estratégicos de entrega en Quito:

| Trayecto Evaluado | Distancia Vial Real (Metros) | Duración de Conducción Estimada (Minutos) | Asimetría Detectada en la Red Vial |
| :--- | :--- | :--- | :--- |
| **De Bodega Arq-AlumVid hacia Sector El Inca** | 3,556 m | 11.4 min (686 s) | El trayecto de ida cruza intersecciones reguladas por semáforos y accesos a vías colectoras. |
| **De Sector El Inca de vuelta a Bodega Arq-AlumVid** | 2,616 m | 8.7 min (527 s) | El retorno es 940 metros más corto y 2.7 minutos más rápido debido al trazado fluido de la Panamericana Norte de subida. |
| **De Bodega Arq-AlumVid hacia La Carolina (Iñaquito)** | 14,800 m | 28.5 min (1,710 s) | Tránsito por autopista perimetral con mayor distancia física pero menor tiempo que cruzar avenidas interiores. |
| **De La Carolina hacia Bodega Arq-AlumVid (Retorno)** | 15,200 m | 34.0 min (2,040 s) | Incremento de 5.5 minutos en horario de la tarde debido al flujo masivo de salida de vehículos hacia el norte. |

*Esta evidencia demuestra concluyentemente que dos puntos con idéntica distancia geodésica en línea recta presentan tiempos y distancias viales notablemente asimétricos, validando la directriz del tutor.*

---

## 9. Articulación Científica con la Investigación del Tutor (Urban Science, 2026)

El desarrollo del módulo logístico de AlumVid se sustenta y articula directamente con los hallazgos de la investigación científica:

> **Chávez-García, N., Salinas-Carrión, J., Navas-Perrone, A., & González-Rodríguez, M. (2026).** *Spatiotemporal Analysis and Forecasting of Traffic Accidents in Ecuador Using DBSCAN and Ensemble Time Series Modeling*. Urban Science, 10(5), 280. https://doi.org/10.3390/urbansci10050280

### Vinculación con la Distribución de Vidrios en AlumVid:
1. **Evitación de Picos Horarios Críticos de Congestión y Siniestros:**  
   El estudio del tutor demostró empíricamente que en las vías urbanas de Quito existen dos ventanas horarias diarias consistentes de alta siniestralidad y saturación:
   * **Pico Matutino (07:00 a 09:00):** Desplazamiento laboral masivo y alta congestión en los accesos norte y sur.
   * **Pico Vespertino (18:00 a 20:00):** Retorno de la población hacia zonas residenciales.  
   Al optimizar el itinerario de AlumVid por **menor tiempo de conducción**, el algoritmo evita saturar las horas pico en vías colapsadas, sugiriendo despachos en horas valle y protegiendo el material vidriero.
2. **Protección de la Carga de Alta Fragilidad:**  
   A diferencia del transporte de mercancías sólidas (paquetería, textiles, alimentos), el vidrio plano presenta un riesgo inminente de estallido ante frenados bruscos o choques por alcance, los cuales son más frecuentes en vías congestionadas identificadas en el estudio. Minimizar el tiempo de permanencia en el tráfico reduce directamente la probabilidad de accidentes.
3. **Respeto a Corredores Troncales Seguros:**  
   El artículo identifica sectores de alta concentración de incidentes (hotspots). Al emplear Google Routes API, el sistema guía a los conductores por vías arteriales principales y señalizadas, evitando desvíos peligrosos por laderas o atajos no aptos para camiones con estructuras tipo caballete.

---

## 10. Matriz de Componentes Implementados en el Software

A continuación se detalla la trazabilidad técnica de todos los archivos y servicios desarrollados en la plataforma AlumVid:

| Capa del Sistema | Archivo / Componente | Funcionalidad Implementada |
| :--- | :--- | :--- |
| **Backend DTO** | `MatrizDistanciaItem.java` | Estructura para registrar duraciones en segundos, distancias en metros y el proveedor que atendió el cálculo. |
| **Backend Servicio** | `GoogleRoutesService.java` | Cliente oficial de Google Routes API v2 con arquitectura resiliente de 3 niveles (Google -> OSRM -> Geodesia). |
| **Backend Lógica** | `LogisticaServiceImpl.java` | 1) Greedy Search basado en tiempo de manejo. 2) Re-enrutado dinámico automático VRSP al cancelar paradas. 3) Bodega Arq-AlumVid (-0.089290, -78.439607). |
| **Pruebas Automatizadas** | `GoogleRoutesServiceTest.java` | Pruebas unitarias de integración que validan el consumo de Google Routes API v2 y los fallbacks con 100% de éxito. |
| **Frontend Desktop** | `admin_dashboard_screen.dart` | Botón **"Re-optimizar (Google Routes)"** para permitir al despachador forzar la re-secuenciación en vivo sobre el mapa interactivo. |
| **Frontend Móvil** | `detalle_ruta_screen.dart` | Conexión con el sensor GPS del chofer para solicitar el re-enrutado dinámico en tiempo real desde su posición geográfica actual. |
| **Navegación Móvil** | `navegacion_destino_screen.dart` | Pantalla de navegación paso a paso con punto de partida configurado en la Bodega Arq-AlumVid. |
| **Infraestructura Gateway** | `compose.yaml / .env` | Mapeo del Gateway a puerto 8085 para evitar conflictos de puertos con procesos locales y asegurar el inicio de sesión. |

---

## 11. Conclusiones y Defensa ante el Tribunal de Grado

1. **Alineación Total con la Retroalimentación Académica:** Se cumplió estrictamente lo indicado por el tutor guía: se aplicó la heurística voraz (**Greedy Search**) alimentada con tiempos de conducción reales de **Google Routes API**, se formalizó el **Vehicle Routing Problem (VRP)** como modelo ideal y se implementó el **Vehicle Rescheduling Problem (VRSP)** mediante re-enrutado reactivo ante imprevistos.
2. **Sustento del Cambio Metodológico:** Se justificó por qué el modelo VRP exacto es inviable para la realidad operativa de una microempresa y por qué la solución anterior por distancia euclídea era ineficiente, demostrando madurez en la toma de decisiones de ingeniería de software.
3. **Robustez y Resiliencia del Sistema:** La arquitectura de tres niveles asegura que la plataforma sea tolerante a fallos externos, manteniendo la continuidad operativa en todo momento.
4. **Legibilidad y Rigor en Lenguaje Natural:** Todo el marco analítico y matemático fue formulado de forma amigable, coherente y comprensible, evitando tecnicismos opacos y asegurando una presentación sólida y convincente para la defensa de grado.
