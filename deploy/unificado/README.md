# Backend único de AlumVid para Railway

Esta alternativa utiliza un componente conectado a GitHub y un componente PostgreSQL con PostGIS. Ejecuta los seis módulos de negocio en una sola JVM, un solo servidor HTTP y un pool de conexiones compartido. No inicia siete procesos Java ni requiere Nginx o un gateway separado.

El código de negocio se compila desde los servicios existentes; no se copió a otro proyecto. Los servicios independientes y `compose.yaml` siguen disponibles. La rama de esta integración es `despliegue_test`.

## Configuración del único componente de aplicación en Railway

| Campo | Valor |
|---|---|
| Repository | `YVghost/alumvid-backend` |
| Branch | `despliegue_test` |
| Root Directory | `/` |
| Config File | `/deploy/unificado/railway.toml` |
| Builder | Dockerfile, definido por el archivo anterior |
| Dockerfile | `deploy/unificado/Dockerfile` |
| Custom Build Command | Vacío |
| Custom Start Command | Vacío: la imagen ejecuta `java -jar /app/app.jar` |
| Healthcheck | `/actuator/health` |
| Healthcheck timeout | 300 segundos |
| Dominio público | Generar en este componente, puerto `8080` |

Watch Paths (también están definidos en `railway.toml`):

```text
services/**
deploy/unificado/**
init.sql
.dockerignore
```

En Variables → Raw Editor, pegar el contenido de `deploy/unificado/.env`. Ese archivo privado se generó con las credenciales locales y Git lo ignora. La plantilla pública es `.env.example`. Railway no lee automáticamente el archivo `.env` del repositorio.

Las referencias `${{PostGIS.…}}` requieren que la base existente se llame exactamente `PostGIS`. Si tiene otro nombre, sustituirlo en las cinco referencias de conexión. No cambiar las credenciales de un volumen PostgreSQL ya inicializado como método para restablecer su contraseña.

No se necesitan `AUTH_URL`, `PEDIDOS_URL` ni las seis variables `*_SERVICE_URL`: los adaptadores comunican los módulos dentro del mismo proceso. El secreto JWT y las credenciales del administrador inicial se conservan en variables. No se incluyen credenciales de PostgreSQL dentro de las aplicaciones Android o Windows.

Conservar la base existente y cambiar la configuración del componente de aplicación actual para apuntar a esta rama y este archivo. No hace falta crear otro componente GitHub. Al reducir el despliegue a un backend único, detener los componentes de aplicación antiguos si los hubiera, sin eliminar la base ni su volumen.

## Base y migraciones

Al iniciar, el backend ejecuta el `init.sql` idempotente del repositorio, que habilita PostGIS y prepara logística. Después aplica Flyway en orden: usuarios, inventario, retazos, pedidos y ubicaciones. Cada módulo conserva su propio `flyway_schema_history`; no se renumeraron ni modificaron migraciones existentes. Hibernate actualiza las entidades de logística después de las migraciones.

La cuenta de conexión necesita permisos para crear los esquemas y habilitar PostGIS. No se borra ni se limpia la base. Antes de conectar una base con datos reales, disponer de su respaldo habitual. El administrador inicial solo se crea cuando todavía no existe un master; sus variables no cambian contraseñas ya guardadas.

## Prueba local de la misma imagen

Docker Desktop debe estar iniciado. Desde la raíz del repositorio, con el `.env` local configurado:

```powershell
docker compose -p alumvid-unificado -f compose.unificado.yaml up -d --build
python scripts/verificar-despliegue.py --url http://localhost:8090
python scripts/probar-unificado.py --url http://localhost:8090
```

La alternativa local usa el puerto `8090`, un PostGIS separado y el volumen `alumvid-unificado_alumvid_unificado_data`. No reemplaza el volumen ni los contenedores del despliegue local original. Para usar otro puerto, definir `UNIFICADO_PORT` antes de ejecutar Compose.

```powershell
docker compose -p alumvid-unificado -f compose.unificado.yaml logs -f backend-unificado
docker stats --no-stream alumvid-unificado-backend-unificado-1
docker compose -p alumvid-unificado -f compose.unificado.yaml down
```

`down` conserva el volumen; no añadir `-v` si se quieren conservar los datos.

Las apps admiten seleccionar el servidor en su configuración: usar `http://localhost:8090` desde Windows, `http://10.0.2.2:8090` desde el emulador Android, la IP LAN del equipo con puerto `8090` desde un teléfono, o el dominio HTTPS del backend en Railway. Se mantienen `/platform-info`, las rutas de la API y `/ws-logistica` en el mismo origen. La selección guardada permite volver al entorno local sin recompilar las apps.

## Pruebas automatizadas

Con JDK 21, Maven y Docker Desktop:

```powershell
mvn -B -ntp -f services/backend-unificado/pom.xml test
```

Testcontainers crea su propio PostGIS temporal. Las pruebas cubren migraciones, permisos, sesiones revocadas, contraseña temporal, retazos, ubicación, reserva y devolución al cancelar, además de la integración logística y pedidos. Las pruebas no necesitan credenciales de tu base real ni una API key de Google.

## Recursos y alcance

`compose.unificado.yaml` limita el backend a 512 MiB y una CPU para comprobar una configuración comparable al plan Free. La JVM utiliza heap máximo de 192 MiB, Serial GC, límites de memoria nativa y menos hilos. PostgreSQL está fuera de ese límite porque es otro componente.

Consultar `VALIDACION.md` para los resultados medidos. Una prueba local satisfactoria no garantiza disponibilidad continua, capacidad para muchos usuarios, saldo suficiente ni que la cuenta permita el despliegue. Es necesario validar también el arranque y los flujos en Railway. No se ha desplegado automáticamente en tu cuenta.
