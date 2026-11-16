# Plataforma Integral AlumVid

[Guia de inicio y apagado seguro](README_INICIO_Y_APAGADO.md): abrir el emulador, ejecutar la app y cerrar el entorno conservando los datos.

> **Proyecto de Titulación - Ingeniería de Software (UDLA)**
> **Tema:** Plataforma de control y monitoreo en tiempo real para la optimización de inventario muerto y rutas logísticas en una microempresa de vidrios y aluminios (**AlumVid**).
> **Autores:** Anthonny Jossue Mosquera Rivadeneira & Mateo Michael Ortega Vacas.


## Estado actual

Esta versión usa siete servicios Spring Boot independientes, PostgreSQL con PostGIS y aplicaciones Flutter para Android y Windows. Se conservan los módulos compartidos, las validaciones de Ecuador y las entregas gestionadas desde pedidos. Ya no hay paneles web administrativos.

- [Despliegue Railway, base externa y ejecución local](DESPLIEGUE_RAILWAY.md).
- [Paquetes y datos para pruebas manuales](entrega-pruebas/README.md).
- [Inicio y apagado local](README_INICIO_Y_APAGADO.md).

## Arranque local

Completar `.env` usando `.env.example` sin reemplazar las credenciales de una base ya creada. Abrir Docker Desktop:

```powershell
.\scripts\iniciar-back.ps1 -Mode Local
```

El gateway está en `http://localhost:8080`. En un teléfono real usar la IP de la PC y la misma red Wi-Fi. Los accesos al sistema usan las cuentas de la base seleccionada; el principal se configura con `MASTER_IDENTIFICATION` y `MASTER_PASSWORD`. No publicar `.env` ni `entrega-pruebas/CREDENCIALES.local.md`.

| Servicio | Puerto local |
|---|---:|
| Gateway | 8080 |
| Usuarios | 8081 |
| Inventario | 8082 |
| Logística | 8083 |
| Retazos | 8084 |
| Pedidos | 8085 |
| Ubicaciones | 8086 |
| PostgreSQL/PostGIS | 5433 |

La base y los esquemas son compartidos. Las migraciones pertenecen a cada servicio. Los datos persisten en `alumvid_pg_data`; `docker compose -f compose.yaml down` conserva el volumen. No usar `-v` para apagar normalmente.

## Railway y modos alternativos

Los archivos `deploy/railway/*/railway.toml` seleccionan Dockerfiles construibles desde la raíz del repositorio. La guía detalla el volumen PostGIS, credenciales, nombres privados, PORT y el orden de despliegue. El gateway público atiende API y WebSocket por un dominio HTTPS/WSS.

Para ejecutar solo el backend en la PC contra una base externa: copiar `.env.external.example` a `.env.external`, completar sus credenciales y usar `scripts/iniciar-back.ps1 -Mode External`. No se copian datos entre bases automáticamente. Las aplicaciones permiten elegir Local o Railway desde el selector Servidor.

## Aplicaciones

Los paquetes se generan sin subir binarios ni secretos al historial Git:

```powershell
.\scripts\build-pruebas.ps1
```

- Android: `entrega-pruebas/android/AlumVid.apk`.
- Windows: `entrega-pruebas/windows/AlumVidAdmin/alumvid_admin_desktop.exe` y `entrega-pruebas/AlumVidAdmin-Windows.zip`.
- Cambiar el servidor desde el login; si Railway no está desplegado, seleccionar Local.

## Verificaciones

```powershell
. .\scripts\mobile-env.ps1
.\scripts\test-all.ps1
.\scripts\test-admin-windows.ps1
.\scripts\iniciar-back.ps1 -Mode RailwayCheck
python scripts/verificar-despliegue.py --url http://localhost:8080
```

Las pruebas nativas necesitan Windows y sus herramientas C++. El backend local de pruebas debe estar levantado. La comprobación HTTP/WebSocket no crea datos. Ver [VALIDACION_RAILWAY.md](VALIDACION_RAILWAY.md) para los resultados y límites de la preparación actual.

## Ramas

`main` es la versión principal. `develop_back`, `develop_app`, `develop_win` y `tests` se crean como copias exactas del mismo commit inicial. Los cambios posteriores pueden desarrollarse por separado y revisarse antes de incorporarlos a main.
