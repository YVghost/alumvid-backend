# Iniciar y apagar el entorno AlumVid

Guía para Windows y PowerShell. Los comandos parten de la **raíz del repositorio**, donde están `compose.yaml`, `scripts/` y `alumvid_mobile/`.

En este equipo la raíz es:

```powershell
Set-Location 'C:\Users\dddma\OneDrive\Escritorio\Codigos_repors\capstone\inventario-service\inventario-service'
```

## 1. Iniciar los servicios

Abre **Docker Desktop** y espera a que su motor esté listo. Después, en una terminal de PowerShell situada en la raíz:

```powershell
. .\scripts\mobile-env.ps1
docker compose -f compose.yaml up -d
docker compose -f compose.yaml ps
```

Si modificaste el código de los servicios y necesitas reconstruir sus imágenes:

```powershell
docker compose -f compose.yaml up -d --build
```

Gestión: desde la app de Windows (`abrir_admin_windows.bat`) o la app Android. Ya no hay portales web.

Los contenedores con estado `starting` pueden necesitar unos segundos para quedar `healthy`.

## 2. Abrir el teléfono Android en una ventana

En esa misma terminal, desde la raíz:

```powershell
flutter emulators
flutter emulators --launch AlumVid_API35
flutter devices
```

Se abrirá la ventana del teléfono emulado. Espera a que termine de arrancar y busca **AlumVid Chofer** en el listado de aplicaciones: el APK ya fue instalado en este dispositivo.

Si el emulador ya está abierto, no vuelvas a lanzarlo; consulta `flutter devices`. Si fue iniciado sin ventana para una prueba automática, ciérralo con el comando de apagado indicado abajo y vuelve a lanzarlo normalmente.

## 3. Ejecutar la app desde el código

Con los servicios y el emulador encendidos:

```powershell
cd alumvid_mobile
flutter pub get
flutter run -d emulator-5554
```

Usa el identificador que muestre `flutter devices`; puede ser distinto de `emulator-5554`. La terminal permanece ocupada mientras se ejecuta `flutter run`.

Dentro de esa terminal:

- `r`: aplicar cambios compatibles mediante hot reload.
- `R`: reiniciar la app mediante hot restart.
- `q`: terminar la ejecución de Flutter.

En el emulador la app utiliza `http://10.0.2.2:8080/api/v1`, que apunta al servidor de tu computadora.

## 4. Ejecutar pruebas o generar el APK

En otra terminal, desde la raíz:

```powershell
. .\scripts\mobile-env.ps1
flutter doctor -v
.\scripts\test-mobile.ps1
```

Para incluir la compilación del APK:

```powershell
.\scripts\test-mobile.ps1 -BuildApk
```

El archivo generado queda en:

```text
alumvid_mobile/build/app/outputs/flutter-apk/app-debug.apk
```

Si ya estás dentro de `alumvid_mobile`, vuelve primero a la raíz con `cd ..`.

## 5. Cerrar todo antes de apagar la computadora

### A. Terminar la aplicación y las pruebas

Si quieres cerrar tu sesión, hazlo dentro de la app mientras el backend sigue encendido. En la terminal donde corre `flutter run`, pulsa **`q`**. Si tienes un servidor web o una prueba continua en otra terminal, termina ese proceso con **Ctrl+C**.

### B. Apagar el emulador

En otra terminal, desde la raíz:

```powershell
. .\scripts\mobile-env.ps1
adb devices
adb -s emulator-5554 emu kill
```

Cambia el identificador si tu emulador aparece con otro. Este comando es para el emulador, no para apagar un teléfono físico. También puedes cerrar su ventana con la **X**. Apagarlo conserva el dispositivo virtual y la aplicación instalada.

### C. Detener los servicios y PostgreSQL

Desde la raíz:

```powershell
docker compose -f compose.yaml down --timeout 30
docker compose -f compose.yaml ps
```

`down` detiene y elimina los contenedores y la red del proyecto, pero **conserva el volumen persistente de PostgreSQL**, sus usuarios y los datos del negocio. La segunda orden debe mostrar que no quedan contenedores activos de este proyecto. Los contenedores de otros proyectos no se detienen.

**No añadas `-v` ni `--volumes` a `down`: eliminarían el volumen de la base de datos. Tampoco uses `docker volume prune` para apagar el proyecto.**

### D. Cerrar herramientas auxiliares (opcional)

Si terminaste de trabajar con Android y Gradle:

```powershell
adb kill-server
& .\alumvid_mobile\android\gradlew.bat --stop
```

`adb kill-server` cierra la conexión ADB local con todos sus dispositivos. `gradlew --stop` detiene los procesos de Gradle de esa versión. Omite estos dos comandos si otras sesiones de desarrollo todavía los necesitan.

Finalmente:

1. En el icono de Docker Desktop de la bandeja de Windows, selecciona **Quit / Salir de Docker Desktop**.
2. Guarda los archivos de VS Code y cierra las terminales.
3. Apaga Windows normalmente.

No hace falta desinstalar Flutter, Android SDK, Java ni las extensiones. Tampoco hace falta borrar `build/` o ejecutar `flutter clean` cada vez que apagas el equipo.

## 6. Volver a trabajar al día siguiente

Abre Docker Desktop y una nueva terminal en la raíz:

```powershell
. .\scripts\mobile-env.ps1
docker compose -f compose.yaml up -d
flutter emulators --launch AlumVid_API35
flutter devices
cd alumvid_mobile
flutter run -d emulator-5554
```

Los contenedores se recrean usando el volumen conservado. No necesitas reinstalar las herramientas ni volver a crear el emulador.

## Si un comando no aparece

- Ejecuta `. .\scripts\mobile-env.ps1` en cada terminal nueva, o reinicia VS Code para que reconozca el PATH actualizado.
- Si `docker` no se conecta, abre Docker Desktop y espera a que su motor termine de iniciar.
- Si Flutter no ve el emulador, espera a que arranque y revisa `adb devices` y `flutter devices`.
- Las rutas locales y las limitaciones funcionales de la app están en [alumvid_mobile/README.md](alumvid_mobile/README.md).

## Administrador nativo de Windows

Abrir `alumvid_admin_desktop\build\windows\x64\runner\Release\alumvid_admin_desktop.exe` después de iniciar Docker. Para ejecutarlo en desarrollo, usar `.\scripts\iniciar-admin.ps1`. Los requisitos C++ y el Modo de desarrollador ya están configurados en este equipo.

Antes de apagar, cerrar sesión en el administrador y cerrar su ventana. Si se ejecutó con Flutter, pulsar `q` en su terminal. Después cerrar el móvil/emulador y detener Docker como se indica arriba. Cerrar el administrador no detiene los servicios ni PostgreSQL.
