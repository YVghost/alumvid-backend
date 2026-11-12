# Validación de integración y Windows

Fecha: 11 de noviembre de 2026. Rama: `mateo_integracion`.

## Backend

| Servicio | Ejecutadas correctamente | Omitidas | Fallos |
|---|---:|---:|---:|
| usuarios | 9 | 0 | 0 |
| inventario | 11 | 0 | 0 |
| retazos | 16 | 0 | 0 |
| pedidos | 42 | 0 | 0 |
| ubicaciones | 8 | 0 | 0 |
| logistica | 6 | 1 | 0 |

Total: 92 pruebas backend correctas y 1 prueba externa de Google opcional omitida. La suite no necesita una clave activa de Google para pasar.

La prueba HTTP real de pedidos–logística pasó 61 verificaciones en la ejecución final (el total puede variar por las consultas de espera), incluyendo entrega parcial fuera de orden, doble confirmación, rechazo sin autenticación, cancelación de venta en reparto, recepción física idempotente, reprogramación y vencimiento antes de entregar. Se limpiaron sus datos QA al terminar. El smoke general del gateway pasó 19 comprobaciones adicionales.

## Aplicaciones

- Administrador: análisis Flutter sin incidencias y 4 pruebas unitarias correctas.
- Windows nativo: 1 prueba completa correcta de login real, navegación por pedidos, retazos y ubicaciones y logout. El ejecutable Release compiló y abrió una ventana que respondió correctamente; se cerró después de comprobarlo.
- Móvil: análisis Flutter sin incidencias y 5 pruebas correctas. APK Debug actualizado para consultar las rutas vinculadas periódicamente.
- No se afirma una prueba de campo GPS/fotografía real: la prueba HTTP utiliza evidencia sintética y el móvil conserva la captura fotográfica simulada.

## Equipo Windows

Se instaló Microsoft Visual Studio Build Tools 2022 17.14.45 con C++, CMake y Windows SDK 10.0.26100.0. Se habilitó el Modo de desarrollador con autorización explícita del usuario. `flutter doctor -v` no reporta incidencias para los destinos configurados.

Ejecutable: `alumvid_admin_desktop/build/windows/x64/runner/Release/alumvid_admin_desktop.exe`. Se puede abrir con `abrir_admin_windows.bat`. Mantener DLL y carpeta `data` junto al ejecutable.

## Reproducción y evidencias locales

```powershell
. .\scripts\mobile-env.ps1
.\scripts\test-all.ps1
python scripts/test-pedidos-logistica.py
python scripts/smoke-platform.py
.\scripts\test-admin-windows.ps1
```

Los informes detallados están en `.cache/integracion/` y `services/*/target/surefire-reports/`, excluidos de Git. Las credenciales se leen del `.env`; no se guardan en las pruebas ni en el repositorio. Hay un respaldo PostgreSQL previo a las migraciones en `.cache/integracion/before-commercial-shipments.dump`.

La integración transaccional necesita la base PostgreSQL compartida actual. Consultar [el contrato y flujo](INTEGRACION_PEDIDOS_LOGISTICA.md) antes de separar bases o cambiar los estados de custodia.
