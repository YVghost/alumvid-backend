param([string]$Device = 'emulator-5554', [switch]$LaunchEmulator)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'mobile-env.ps1')
if ($LaunchEmulator) {
    & flutter emulators --launch AlumVid_API35
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar el emulador.' }
    & adb -s $Device wait-for-device
}
Push-Location (Join-Path $taskRoot 'alumvid_mobile')
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'No se resolvieron las dependencias.' }
    & flutter run -d $Device --dart-define-from-file=../config/flutter.local.json
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar la aplicacion.' }
} finally { Pop-Location }
