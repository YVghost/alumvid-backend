# Preparación Railway y entornos locales

Fecha: 15 de noviembre de 2026. Se conservó el código de la rama de trabajo actual y sus eliminaciones de documentación; no se incorporaron cambios de otras ramas.

## Backend

| Servicio | Correctas | Omitidas | Fallos |
|---|---:|---:|---:|
| usuarios | 13 | 0 | 0 |
| inventario | 11 | 0 | 0 |
| retazos | 16 | 0 | 0 |
| pedidos | 42 | 0 | 0 |
| ubicaciones | 8 | 0 | 0 |
| logistica | 11 | 1 | 0 |

Total: 101 pruebas correctas y 1 prueba externa opcional omitida. Se ajustó un dato de prueba que usaba la identificación inicial del principal, en lugar de una cédula sintética válida, para comprobar duplicados sin cambiar la validación ecuatoriana.

## Construcción y despliegue simulados

- Las siete imágenes de aplicación se construyeron con Docker.
- La imagen PostgreSQL/PostGIS de Railway se construyó y arrancó con una base nueva aislada: PostGIS 3.4.3, tres esquemas iniciales y cuatro tablas de logística. Se eliminó solo el contenedor de validación; no se tocaron volúmenes existentes.
- El gateway de Railway se ejecutó en Docker local: ocho comprobaciones REST y dos handshakes WebSocket válidos por el mismo puerto público, sin crear datos.
- Se validó el Compose de base externa sin intentar conectar a un servidor remoto.

## Aplicaciones

- Análisis Flutter de Android y Windows sin incidencias.
- Pruebas de escritorio: 11 correctas, incluyendo normalización de URL, perfiles y WSS sin puerto local.
- Pruebas móviles: 14 correctas y dos omitidas preexistentes.
- Prueba nativa Windows: login, módulos de pedidos/piezas/bodega y logout correctos, adaptada a los módulos actuales.
- APK Release y ejecutable Windows Release regenerados en entrega-pruebas con build number 2. Los paquetes previos se respaldaron en `.cache/binarios-antes-railway-*`.

## Límites verificados

No se desplegó ni se conectó a un proyecto Railway real: aún hay que configurar el proyecto, sus credenciales y el dominio público siguiendo la guía. HTTPS/WSS se preparó y probó a nivel de URLs y proxy local; el certificado real debe comprobarse con el dominio desplegado.

No se migraron ni copiaron los datos locales a Railway. Seleccionar Local y Railway conecta a bases diferentes según el backend elegido; no hay sincronización automática. No se cambiaron las reglas de negocio del usuario.

El respaldo local de ramas previo a la reorganización es `.cache/ramas-antes-main-20261115.bundle`. No se publica en Git ni conserva contraseñas del `.env` fuera del repositorio.
