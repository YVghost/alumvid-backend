# Plataforma Integral AlumVid

> **Proyecto de Titulación - Ingeniería de Software (UDLA)**  
> **Tema:** Plataforma de control y monitoreo en tiempo real para la optimización de inventario muerto y rutas logísticas en una microempresa de vidrios y aluminios (**AlumVid**).  
> **Autores:** Anthonny Jossue Mosquera Rivadeneira & Mateo Michael Ortega Vacas.

---

## 1. Arquitectura General del Sistema

El ecosistema de software está estructurado bajo una **arquitectura de microservicios desacoplada** (Java 21 / Spring Boot 3.4), persistencia relacional geoespacial (**PostgreSQL 16 + PostGIS 3.4**), un **API Gateway centralizado** con seguridad RBAC basada en tokens JWT, un **Dashboard Administrativo Web** y una **Aplicación Móvil Nativa (Flutter)** para los choferes y operarios en campo.

```text
                                  ┌─────────────────────────────┐
                                  │      Clientes / Frontend     │
                                  │  - admin-dashboard (Web)    │
                                  │  - alumvid_mobile (Flutter) │
                                  └──────────────┬──────────────┘
                                                 │ HTTP / REST / WebSocket
                                                 ▼
                                  ┌─────────────────────────────┐
                                  │       API Gateway MVC       │
                                  │    puerto :8080 (AlumVid)   │
                                  └──────┬──────────┬──────────┬┘
                  /api/auth, /api/admin  │          │          │ /api/v1/logistica,
                                         │          │          │ /ws-logistica
                                         ▼          │          ▼
                        ┌──────────────────┐        │ ┌──────────────────┐
                        │ usuarios-service │        │ │logistica-service │
                        │   puerto :8081   │        │ │   puerto :8083   │
                        └────────┬─────────┘        │ └────────┬─────────┘
                                 │                  │          │
                                 │   /api/products  │          │
                                 │                  ▼          │
                                 │        ┌──────────────────┐ │
                                 │        │inventario-service│ │
                                 │        │   puerto :8082   │ │
                                 │        └────────┬─────────┘ │
                                 │                 │           │
                                 ▼                 ▼           ▼
                        ┌────────────────────────────────────────┐
                        │      PostgreSQL 16 + PostGIS 3.4       │
                        │           puerto :5433:5432            │
                        │               alumvid_db               │
                        │  Esquemas: usuarios, inventario, logis │
                        └────────────────────────────────────────┘
```

---

## 2. Organización del Repositorio

```text
├── services/
│   ├── gateway-service/       # API Gateway unificado (Spring Cloud Gateway MVC, puerto 8080)
│   ├── usuarios-service/      # RBAC, autenticacion JWT/Bearer, auditoria y portal (puerto 8081)
│   ├── inventario-service/    # Catalogo de productos, existencias y movimientos (puerto 8082)
│   └── logistica-service/     # Rutas multi-destino, PostGIS, telemetria y e-PoD (puerto 8083)
├── admin-dashboard/           # Panel web del administrador (Google Maps, Kanban, Telemetria)
├── alumvid_mobile/            # Aplicacion movil Flutter para choferes (Camara PoD, Firma, GPS)
├── DOCUMENTACION/             # Tesis Mosquera-Ortega (.docx, .pptx) y Catalogo AlumVid (.xls)
├── scripts/                   # Scripts de prueba y verificacion automatizada
├── docker-compose.yml         # Orquestacion de infraestructura y microservicios
├── compose.yaml               # Alias compatible Docker Compose v2
├── init.sql                   # Inicializacion DDL de PostGIS y esquemas relacionales
├── .env.example               # Plantilla de variables de entorno
├── pom.xml                    # POM agregador raiz Maven
└── mvnw / mvnw.cmd            # Maven Wrapper
```

---

## 3. Matriz de Servicios y Puertos

| Servicio | Puerto Interno | Puerto Host | Descripción | Base de Datos / Esquema |
|---|---|---|---|---|
| **API Gateway** | `8080` | `8080` | Enrutamiento perimetral, CORS y recursos estáticos | N/A |
| **Usuarios & Auth** | `8081` | `8081` | Control de acceso, JWT, auditoría, sesiones y admin | `alumvid_db` / `usuarios` |
| **Inventario** | `8082` | `8082` | Catálogo de perfiles/vidrios, movimientos y stock | `alumvid_db` / `inventario` |
| **Logística & Despacho**| `8083` | `8083` | Rutas multi-destino, auditoría PostGIS, WebSocket | `alumvid_db` / `logistica` |
| **PostgreSQL / PostGIS**| `5432` | `5433` | Motor relacional y computo espacial geoespacial | `alumvid_db` |

---

## 4. Despliegue con Docker Compose

1. Configura el archivo de variables de entorno:
   ```powershell
   Copy-Item .env.example .env
   ```
2. Inicia todos los servicios e infraestructura:
   ```powershell
   docker compose up -d --build
   ```
3. Verifica el estado de los contenedores:
   ```powershell
   docker compose ps
   ```

### Accesos Disponibles:
- **API Gateway & Dashboard Administrador:** [http://localhost:8080](http://localhost:8080)
- **Portal de Usuarios:** [http://localhost:8081](http://localhost:8081)
- **Portal de Inventario:** [http://localhost:8082](http://localhost:8082)
- **Credenciales Iniciales (Master Admin):**
  - **Identificación:** `1700000000` (o `admin@alumvid.com`)
  - **Contraseña:** `AlumVidAdmin2026!`

---

## 5. Compilación y Pruebas Locales (Maven)

Desde la raíz del repositorio, gracias al POM agregador:

```powershell
# Compilar y empaquetar todos los microservicios sin pruebas
.\mvnw.cmd clean package -DskipTests

# Ejecutar la suite completa de verificacion
.\scripts\test-all.ps1
```

O compilar servicios individualmente:
```powershell
.\mvnw.cmd -f services/usuarios-service/pom.xml compile
.\mvnw.cmd -f services/inventario-service/pom.xml compile
.\mvnw.cmd -f services/logistica-service/pom.xml compile
.\mvnw.cmd -f services/gateway-service/pom.xml compile
```

---

## 6. Endpoints Principales del API Gateway (`http://localhost:8080`)

| Método | Endpoint | Microservicio Destino | Descripción |
|---|---|---|---|
| `POST` | `/api/v1/auth/login` | `usuarios-service` | Login con cédula o email. Devuelve token JWT |
| `GET` | `/api/auth/me` | `usuarios-service` | Perfil y roles del usuario autenticado |
| `POST` | `/api/auth/password` | `usuarios-service` | Cambio obligatorio o manual de contraseña |
| `GET` | `/api/admin/users` | `usuarios-service` | Listado administrativo de colaboradores |
| `GET` | `/api/admin/audit` | `usuarios-service` | Bitácora de auditoría de seguridad |
| `GET` | `/api/products` | `inventario-service`| Catálogo paginado con filtros de stock |
| `POST` | `/api/products/{id}/movements` | `inventario-service`| Registro idempotente de entradas/salidas/ajustes |
| `GET` | `/api/v1/logistica/pedidos` | `logistica-service` | Consulta de pedidos para despacho |
| `POST` | `/api/v1/logistica/rutas/multi-destino` | `logistica-service` | Planificación de ruta multi-parada con TSP |
| `POST` | `/api/v1/logistica/despachos/{id}/cerrar`| `logistica-service`| Cierre de entrega con e-PoD (foto, firma y GPS) |
| `WS` | `/ws-logistica` | `logistica-service` | Streaming bidireccional STOMP de telemetría GPS |

---

## 7. Aplicación Móvil (`alumvid_mobile`)

Desarrollada en Flutter para dispositivos Android / iOS de los choferes:
- **Login integrado:** Soporta autenticación por Cédula ecuatoriana o correo.
- **Rutas del día:** Lista de despachos asignados en orden óptimo.
- **Navegación en vivo:** Brújula y mapa interactivo hacia la ubicación del cliente.
- **Captura e-PoD:** Obliga a tomar fotografía en vivo del material, registrar firma digital y audita la coordenada GPS frente a la geocerca de PostGIS.
