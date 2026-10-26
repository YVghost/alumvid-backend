# AlumVid — Centro de Control y Monitoreo Logístico (Administrador)

Aplicación nativa de **Escritorio (Windows)** y **Móvil (Android)** para la supervisión y gestión en tiempo real de rutas, paradas, telemetría satelital y comprobantes fehacientes de entrega (**e-PoD**) de **AlumVid**.

---

## 1. Características Principales

* **Mapa Satelital Google Maps en Tiempo Real:**
  * Selector interactivo de capas: **Calles**, **Satélite**, **Híbrido** y **Terreno**.
  * Trazado vial real (OSRM) siguiendo las calles de Quito entre Bodega Central y cada destino.
  * Geocercas circulares de tolerancia (150m PostGIS) alrededor de las paradas.
  * Marcadores dinámicos de vehículos de choferes con velocidad en km/h y orientación de rumbo.
* **Diseño Responsivo Adaptativo:**
  * **Pantalla Dividida (Desktop):** 65% mapa satelital interactivo + 35% panel de control con métricas y lista de rutas.
  * **Modo Móvil:** Navegación por pestañas (*Mapa Satelital* y *Rutas/Paradas*) con hojas de inspección inferior.
* **Control Operativo Dinámico (Intervención en Caliente):**
  * Creación de rutas multi-destino con optimización TSP de orden de paradas.
  * Agregar destinos o paradas imprevistas a rutas activas o pendientes.
  * Reordenar paradas y reasignar choferes en vivo.
  * Iniciar y cancelar rutas con registro de auditoría.
* **Supervisión y Auditoría e-PoD:**
  * Consulta visual en 1 clic de la fotografía del vidrio entregado en obra.
  * Firma digitalizada del receptor.
  * Cálculo de desviación métrica PostGIS con semáforo verde (<150m) o alerta roja de desvío (>150m).
* **Conectividad Inteligente:**
  * En Windows Desktop se conecta automáticamente a `http://localhost:8080`.
  * En Android se conecta a `http://10.0.2.2:8080` (emulador) o permite configurar la IP local con el botón de ajustes ⚙️.

---

## 2. Ejecución

### En Windows Escritorio:
```powershell
cd alumvid_admin_desktop
flutter run -d windows
```

O ejecutar directamente el ejecutable compilado:
```powershell
.\build\windows\x64\runner\Debug\alumvid_admin_desktop.exe
```

### En Emulador o Dispositivo Android:
```powershell
cd alumvid_admin_desktop
flutter run -d android
```

---

## 3. Credenciales de Acceso

* **Identificación:** `1700000000` (o `admin@alumvid.com`)
* **Contraseña:** `AlumVidAdmin2026!`
