# Entrega para pruebas manuales (teléfono real + PC)

```
entrega-pruebas/
├── android/AlumVid-Chofer.apk        App móvil del chofer (release)      ← local, no se sube a Git
├── AlumVidAdmin-Windows.zip          Administrador de Windows comprimido   ← local, no se sube a Git
├── windows/AlumVidAdmin/             Administrador de Windows (copiar la carpeta completa)
│   └── alumvid_admin_desktop.exe
├── windows/mostrar_ip_servidor.bat   Muestra la IP actual del backend
├── DATOS_DEMO.json                   IDs de los datos ficticios creados
├── CREDENCIALES.local.md             Usuarios y contraseñas demo        ← local, no se sube a Git
└── estado.local.json                 Estado del script de datos demo    ← local, no se sube a Git
```

Los binarios y las contraseñas están en `.gitignore`. Para regenerarlos ver "Recompilar" abajo.

## 1. Encender el backend (PC)

1. Ejecutar `iniciar_todo.bat` en la raíz del proyecto (Docker Desktop abierto).
2. Ejecutar `mostrar_ip_servidor.bat`: indica si el backend responde y la dirección a usar desde el teléfono
   (por ejemplo `http://192.168.1.31:8080`).
3. Solo la primera vez, si el teléfono no conecta: abrir PowerShell **como administrador** y permitir el puerto 8080:
   ```powershell
   New-NetFirewallRule -DisplayName "AlumVid Gateway 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Private,Public
   ```

## 2. Administrador en la PC

Abrir `windows/AlumVidAdmin/alumvid_admin_desktop.exe` (no mover el .exe fuera de su carpeta: necesita las DLL y `data/`).
Se conecta a `http://localhost:8080`.

## 3. App móvil en un teléfono Android real

1. Copiar `android/AlumVid-Chofer.apk` al teléfono e instalarlo (permitir "instalar apps de origen desconocido").
2. Conectar el teléfono **a la misma Wi‑Fi que la PC**.
3. En el login, la línea superior muestra el servidor actual. Si cambiaste de red:
   - **Servidor → Buscar automáticamente**: la app recorre la red Wi‑Fi y encuentra la PC con el backend.
   - O escribir a mano la dirección que muestra `mostrar_ip_servidor.bat`.
4. Si inicias sesión y el servidor guardado no responde (porque cambió la IP), la app busca el servidor sola y reintenta.

> Las redes de invitados, universidades o algunos hotspots aíslan a los dispositivos entre sí; ahí ni la búsqueda ni la IP manual funcionan. Usa un hotspot del propio teléfono o una red doméstica.

## 4. Usuarios de prueba

Las contraseñas están en `CREDENCIALES.local.md` (solo en la PC que generó los datos).

| Usuario | Rol | Para probar |
|---|---|---|
| DEMO-729717-ADMIN | ADMINISTRADOR | Administrador de Windows: usuarios, inventario, pedidos, rutas |
| DEMO-729717-VENTAS | VENDEDOR | Crear y consultar pedidos |
| DEMO-729717-BODEGA | BODEGUERO | Preparar pedidos, retazos, ubicaciones |
| DEMO-729717-CHOFER1 | CHOFER | App móvil: ruta pendiente de iniciar |
| DEMO-729717-CHOFER2 | CHOFER | App móvil: ruta en curso |
| DEMO-729717-MULTI | VENDEDOR, BODEGUERO, CHOFER | Usuario con varios roles |
| DEMO-729717-TEMP | CHOFER | Obliga a cambiar la contraseña en el primer ingreso |
| DEMO-729717-INACTIVO | VENDEDOR | Desactivado: el login debe rechazarse |

## 5. Datos ficticios

Todo lleva el prefijo `DEMO-729717` y no reemplaza datos existentes.

- **Clientes:** DEMO Ana Pruebas, DEMO Constructora Ejemplo, DEMO Carlos Demostración.
- **Productos:** DEMO Tornillos, DEMO Silicona (stock bajo), DEMO Cerradura (sin stock),
  DEMO Vidrio marrón 183 x 244 cm, DEMO Perfil aluminio 6.40 m (con retazos).
- **Ubicaciones:** DEMO-729717-A3, B3, C1.

**Pedidos por escenario** (número de pedido → estado):

| Nº | Escenario | Estado |
|---|---|---|
| 12 | Reservado | RESERVADO |
| 13 | Falta material | PENDIENTE_MATERIAL |
| 14 | Retiro en local listo | LISTO |
| 15 | Retiro parcial | PARCIAL |
| 16 | Listo para despachar | LISTO |
| 17 | Ruta asignada a CHOFER1 sin iniciar | EN_REPARTO |
| 18 | Ruta en curso de CHOFER2 | EN_REPARTO |
| 19 | Reparto cancelado, retorno pendiente | CANCELADO |
| 20 | Retrasado | RETRASADO |
| 21 | Entregado por retiro | ENTREGADO |
| 22 | Corte cancelado, devuelto al inventario | CANCELADO |
| 23 | Reserva vencida | VENCIDO |
| 24 | Entregado por logística (con evidencia) | ENTREGADO |

## Recompilar

```powershell
. .\scripts\mobile-env.ps1
# APK (la IP es solo el valor inicial; luego se cambia desde la app)
cd alumvid_mobile;        flutter build apk --release --dart-define=API_BASE_URL=http://<IP-PC>:8080/api/v1 --dart-define-from-file=..\config\flutter.local.json
# Administrador Windows
cd ..\alumvid_admin_desktop; flutter build windows --release --dart-define-from-file=..\config\flutter.local.json
```

Datos demo: `python scripts/seed-demo.py` (idempotente; `--nuevo-lote` crea otro conjunto con prefijo nuevo).
