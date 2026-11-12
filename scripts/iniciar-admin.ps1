param([string]$Device = 'windows')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'mobile-env.ps1')
if ($Device -eq 'windows') {
    & flutter config --enable-windows-desktop
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo habilitar Windows Desktop.' }
}
Push-Location (Join-Path $taskRoot 'alumvid_admin_desktop')
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'No se resolvieron las dependencias.' }
    & flutter run -d $Device --dart-define-from-file=../config/flutter.local.json
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar el administrador.' }
} finally { Pop-Location }
