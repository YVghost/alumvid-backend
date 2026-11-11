# Aplicación móvil AlumVid

Aplicación Flutter para conductores: login, consulta de rutas y paradas, navegación, ubicación y registro e-PoD. Esta rama es `services`; las modificaciones móviles posteriores de `develop` no se mezclaron al actualizar referencias.

## Entorno preparado en Windows

Validado el **11 de noviembre de 2026**:

- Flutter estable **3.47.9**, Dart **3.13.7**.
- Temurin JDK **21.0.13**, configurado específicamente para Flutter.
- Android SDK Platform **36**, build-tools **36.0.0**, platform-tools, command-line tools.
- NDK **28.2.13676358**, CMake **3.22.1**.
- Android Emulator, imagen Android **35 Google APIs x86_64** y dispositivo `AlumVid_API35`.
- Extensiones **Dart-Code.flutter** y **Dart-Code.dart-code** de VS Code.

SDK Flutter: `%USERPROFILE%\dev\sdk\flutter`. Java: `%USERPROFILE%\dev\jdk-21`. Android: `%LOCALAPPDATA%\Android\Sdk`. Se agregaron Flutter y Android al PATH del usuario; reiniciar VS Code y sus terminales para que lo detecten. No se cambió el Java predeterminado de otros proyectos.

Se configuraron los objetivos Android y web. Escritorio Windows está deshabilitado en Flutter para no exigir enlaces simbólicos/Developer Mode ni instalar Visual Studio C++; no es necesario para probar esta app móvil. iOS requiere una máquina macOS con Xcode y no se compiló en este equipo.

## Activar y probar

Desde la raíz del repositorio:

```powershell
. .\scripts\mobile-env.ps1
flutter doctor -v
.\scripts\test-mobile.ps1
# Incluye compilación Android:
.\scripts\test-mobile.ps1 -BuildApk
```

El script admite rutas alternativas para otros equipos:

```powershell
. .\scripts\mobile-env.ps1 -FlutterSdk C:\ruta\flutter -AndroidSdk C:\ruta\Sdk -JavaSdk C:\ruta\jdk-21
```

Arrancar el backend conforme al README principal y ejecutar en un emulador:

```powershell
docker compose -f compose.yaml up -d
flutter emulators
flutter emulators --launch AlumVid_API35
flutter devices
cd alumvid_mobile
flutter run -d emulator-5554
```

Usar el identificador que muestre `flutter devices`; puede cambiar si hay otros emuladores abiertos. Para detener solo ese emulador: `adb -s emulator-5554 emu kill`.

El APK de depuración queda en `alumvid_mobile/build/app/outputs/flutter-apk/app-debug.apk`. Se instala con `adb -s emulator-5554 install -r <ruta-del-apk>` o mediante `flutter run`. Los archivos compilados y las rutas locales no se publican en Git.

## Conexión al servidor

- Emulador Android: `http://10.0.2.2:8080/api/v1` por defecto.
- Web/escritorio/simulador iOS: `http://localhost:8080/api/v1` por defecto.
- Teléfono físico: usar la IP del equipo servidor, no `localhost` ni `10.0.2.2`.

```powershell
flutter run -d <id-del-telefono> --dart-define=API_BASE_URL=http://IP_DEL_SERVIDOR:8080/api/v1
```

El teléfono debe estar conectado y tener depuración USB habilitada; el puerto debe ser accesible desde su red. La compilación **debug** permite HTTP local. Las compilaciones de producción necesitan configurar HTTPS y firma propia: actualmente release conserva la firma de depuración del proyecto.

No hay usuarios precargados en la pantalla de login. Usar una cuenta existente configurada en el backend; no se crea un conductor de ejemplo al instalar Flutter. Cambiar una contraseña en `.env` no cambia automáticamente la contraseña de una cuenta ya creada en la base persistente.

## Revisión funcional de esta rama

Implementado: login con identificación/correo, listado de rutas del conductor, detalle de paradas, navegación con OSRM/mapa, acceso a ubicación, envío de telemetría, firma táctil y petición de cierre de entrega. El cierre de sesión ahora intenta revocar la sesión del servidor y limpia las credenciales locales; sin red limpia la sesión local y el token remoto conserva su vencimiento.

Limitaciones que deben resolverse antes de validar entregas reales:

1. **La fotografía está simulada**: el botón de captura usa una imagen fija de un píxel. Tener `image_picker` instalado no significa que exista captura real de cámara.
2. **Hay coordenadas de respaldo** cuando falla el GPS, incluyendo el destino del pedido. Ese comportamiento es de demostración y no prueba que el conductor esté físicamente en el lugar.
3. Esta revisión de `services` no incorpora el flujo móvil de cambio obligatorio de contraseña temporal que aparece en cambios más recientes de `develop`.
4. No hay pantallas móviles de inventario, retazos, pedidos comerciales ni ubicaciones; esta app está orientada al conductor. Esas APIs y los portales administrativos son módulos separados.
5. No se implementa una cola completa de operaciones sin conexión ni protección de token mediante almacenamiento seguro nativo; actualmente se usa SharedPreferences.
6. La integración automática entre pedido comercial y logística sigue pendiente en el backend. Probar rutas logísticas no valida esa integración.

Las pruebas de instalación/login no registran entregas ni crean productos o ventas ficticias en la base de trabajo.

## Fuentes de instalación

[Flutter: instalación oficial](https://docs.flutter.dev/install/manual), [configuración Android](https://docs.flutter.dev/platform-integration/android/setup), [Android SDK y herramientas oficiales](https://developer.android.com/studio).

## Resultado de validacion

- `flutter doctor -v`: sin incidencias para los objetivos configurados.
- `flutter analyze`: sin incidencias.
- `flutter test`: 4 pruebas aprobadas.
- `flutter build web --release`: compilacion generada; login, consulta de rutas y logout verificados en Chrome contra el backend existente.
- APK debug generado, instalado y abierto en `AlumVid_API35`; pantalla de login inspeccionada.

Gradle 8.14, AGP 8.11.1 y Kotlin 2.2.20 siguen compilando, pero Flutter muestra avisos sobre sus minimos futuros. La migracion mayor a Gradle 9/AGP debe hacerse por separado y no se forzo durante esta preparacion. Las pruebas anteriores no certifican camara/GPS reales ni una entrega fisica.
