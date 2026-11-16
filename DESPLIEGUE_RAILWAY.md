# Backend y PostgreSQL en Railway; pruebas locales conservadas

Las reglas de negocio y los módulos actuales se conservan. La configuración distingue el backend local, el backend con base externa y el despliegue completo en Railway. Las bases no se sincronizan automáticamente ni se intercambian durante una operación.

## 1. Local, como hasta ahora

Completar `.env` a partir de `.env.example` y abrir Docker Desktop:

```powershell
.\scripts\iniciar-back.ps1 -Mode Local
```

Equivale a `docker compose -f compose.yaml up -d --build --wait`. Conserva el volumen `alumvid_pg_data`. Para apagar: `docker compose -f compose.yaml down` (sin `-v`). El gateway sigue en 8080 y logística local en 8083.

## 2. Proyecto Railway

Crear **ocho servicios** desde este repositorio y rama `main`. Mantener Root Directory `/` en todos. En Settings → Config as Code indicar el archivo de la tabla. Cada archivo selecciona su Dockerfile y healthcheck; Railway no ejecuta Compose ni lee automáticamente el `.env` privado de la PC.

| Nombre exacto en Railway | Config file | PORT | Exposición |
|---|---|---:|---|
| postgres | `/deploy/railway/postgres/railway.toml` | 5432 | Privada, volumen |
| usuarios | `/deploy/railway/usuarios/railway.toml` | 8081 | Privada |
| inventario | `/deploy/railway/inventario/railway.toml` | 8082 | Privada |
| logistica | `/deploy/railway/logistica/railway.toml` | 8083 | Privada |
| retazos | `/deploy/railway/retazos/railway.toml` | 8084 | Privada |
| pedidos | `/deploy/railway/pedidos/railway.toml` | 8085 | Privada |
| ubicaciones | `/deploy/railway/ubicaciones/railway.toml` | 8086 | Privada |
| gateway | `/deploy/railway/gateway/railway.toml` | 8080 | Dominio HTTPS público |

En cada servicio configurar su PORT de la tabla; en los seis microservicios configurar `SERVER_ADDRESS=::` para la red privada. Los Dockerfiles están preparados con contexto raíz, Java 21, caché Maven y reintentos. El gateway público incluye un proxy Nginx: las rutas REST llegan al gateway Spring y `/ws-logistica` llega al broker privado. Las apps usan HTTPS/WSS del mismo dominio sin exponer 8083 a Internet.

### Base obligatoria con PostGIS

El servicio `postgres` usa **postgis/postgis:16-3.4** e inicializa `init.sql`. Una plantilla PostgreSQL sin PostGIS no basta para las geometrías de logística.

Agregar un volumen Railway en `/var/lib/postgresql/data`. Variables del servicio postgres:

```dotenv
POSTGRES_DB=alumvid_db
POSTGRES_USER=alumvid_admin
POSTGRES_PASSWORD=UNA_CLAVE_ALEATORIA_REAL
PGDATA=/var/lib/postgresql/data/pgdata
```

El script inicial solo se ejecuta con un volumen nuevo. Cambiar una variable no cambia la contraseña de un volumen ya inicializado. Si se usa una base existente con PostGIS, inicializar los esquemas con `init.sql` antes de desplegar; nunca borrar un volumen para corregir credenciales. Este Docker PostGIS no añade TLS por sí solo: para sus conexiones privadas se usa `DB_SSLMODE=prefer`. En un proveedor que exija TLS, usar `require` o una URL JDBC con sus certificados apropiados.

### Variables del backend

La plantilla `deploy/railway/.env.example` documenta las referencias de Railway (`${{postgres.POSTGRES_PASSWORD}}`, etc.). Copiar **solo los bloques correspondientes** a cada servicio, sustituyendo los marcadores. No importar el archivo completo a todos los servicios.

En los seis microservicios:

```dotenv
DB_HOST=${{postgres.RAILWAY_PRIVATE_DOMAIN}}
DB_PORT=5432
DB_NAME=${{postgres.POSTGRES_DB}}
DB_USER=${{postgres.POSTGRES_USER}}
DB_PASSWORD=${{postgres.POSTGRES_PASSWORD}}
DB_SSLMODE=prefer
DB_POOL_SIZE=5
SERVER_ADDRESS=::
AUTH_URL=http://${{usuarios.RAILWAY_PRIVATE_DOMAIN}}:8081
```

Logística necesita además `PEDIDOS_URL=http://${{pedidos.RAILWAY_PRIVATE_DOMAIN}}:8085` y `GOOGLE_MAPS_API_KEY` si se usa Google Routes. Usuarios necesita `MASTER_IDENTIFICATION`, `MASTER_NAME`, `MASTER_PASSWORD`, `JWT_SECRET` y `JWT_EXPIRATION_HOURS`. La identificación principal debe corresponder a tu configuración; las altas de empleados mantienen la validación ecuatoriana existente. Compartir el mismo JWT_SECRET con logística si se configura allí. Las claves no van en Git.

También se admiten `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER` y `PGPASSWORD`. Para una URL completa usar `DB_URL=jdbc:postgresql://host:puerto/base?sslmode=require`; una URL `postgresql://usuario:clave@host/...` sin el prefijo JDBC no es equivalente. No pegar contraseñas de PostgreSQL en las apps.

En `gateway` copiar los seis `*_SERVICE_URL` de la plantilla; apuntan a los nombres privados y puertos de la tabla. Generar un único dominio público para ese servicio. Ejemplo de dirección para las apps: `https://tu-gateway.up.railway.app`.

### Orden del primer despliegue

Base → usuarios → inventario → retazos → pedidos → ubicaciones. Logística puede desplegarse cuando la base esté inicializada; para completar entregas necesita pedidos operativo. Desplegar gateway al final. Las migraciones actuales comparten esquemas y necesitan ese orden de inicialización; un redeploy posterior conserva los datos. No ejecutar `seed-demo.py` contra producción: las pruebas ficticias locales y las credenciales se mantienen aparte.

La configuración queda lista para desplegar, pero no crea un proyecto Railway ni genera credenciales/domino por sí sola. Tras obtenerlos, completar variables en Railway y comprobar `/platform-info`, los seis healthchecks y una conexión WSS.

## 3. Backend en la PC con base externa

Copiar `.env.external.example` a `.env.external` (ignorado por Git) y completar DB_HOST, DB_PORT, DB_NAME, DB_USER y DB_PASSWORD. Desde fuera de Railway se usa su host/puerto públicos TCP, no `*.railway.internal`. PostGIS y los esquemas deben existir. Elegir el SSL que realmente soporte esa base.

Antes de cambiar de modalidad, detener la anterior sin eliminar volúmenes:

```powershell
docker compose -f compose.yaml down
.\scripts\iniciar-back.ps1 -Mode External
# Para detener la modalidad externa:
docker compose --env-file .env.external -f compose.external-db.yaml down
# Para regresar a la base local:
.\scripts\iniciar-back.ps1 -Mode Local
```

El Compose externo no crea PostgreSQL local y conecta los seis servicios a la misma base externa. No migra los datos locales a la nube ni los mezcla. En ambos modos las apps pueden usar localhost/IP de la PC; si todo el backend está en Railway se selecciona su dominio público.

## 4. Android y Windows

En el login → **Servidor**, elegir **Local** o **Railway**. Si no se configuró un dominio Railway, pegar su URL HTTPS y guardar. Cada perfil recuerda la dirección ingresada. En el teléfono, el modo local necesita la IP de la PC o Buscar automáticamente en la misma Wi-Fi; en Windows localhost funciona en la misma computadora.

Al cambiar de servidor se cierra la sesión anterior y se vuelve a ingresar con las cuentas de la base elegida. Si Railway falla, seleccionar Local explícitamente: no se reenvían ventas a otra base en silencio. Las cuentas y existencias de las dos bases pueden ser distintas.

Se pueden definir `LOCAL_API_URL` y `RAILWAY_API_URL` en el `.env` de la PC para incorporarlos a nuevos binarios. Solo se incluyen URLs públicas, no credenciales de la base. No hace falta recompilar para cambiar la dirección desde las apps.

```powershell
.\scripts\build-pruebas.ps1
```

Actualiza `entrega-pruebas/android/AlumVid.apk`, `entrega-pruebas/windows/AlumVidAdmin/` y su ZIP. Conservar toda la carpeta Windows, no solo el .exe. Los binarios y secretos siguen excluidos del historial Git.

## 5. Validación del edge Railway en local

```powershell
.\scripts\iniciar-back.ps1 -Mode RailwayCheck
python scripts/verificar-despliegue.py --url http://localhost:8080
```

Prueba `/platform-info` y el Upgrade WebSocket por la misma entrada pública. El proceso no crea productos, pedidos ni usuarios. Para probar en Railway usar la misma orden con la URL HTTPS real. Esta verificación no acredita un despliegue real hasta disponer de ese dominio.

Referencias oficiales: [Docker y Compose en Railway](https://railway.com/guides/docker-compose), [configuración como código](https://docs.railway.com/config-as-code/reference), [red privada](https://docs.railway.com/networking/private-networking), [PostgreSQL y extensiones](https://docs.railway.com/databases/postgresql).
