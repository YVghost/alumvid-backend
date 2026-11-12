$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'mobile-env.ps1')
$taskConfig = @{}
foreach ($taskLine in Get-Content -LiteralPath (Join-Path $taskRoot '.env')) {
    if ($taskLine -match '^([A-Z_]+)=(.*)$') { $taskConfig[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'") }
}
$env:ALUMVID_QA_IDENTIFIER = $taskConfig['MASTER_IDENTIFICATION']
$env:ALUMVID_QA_PASSWORD = $taskConfig['MASTER_PASSWORD']
Push-Location (Join-Path $taskRoot 'alumvid_admin_desktop')
try {
    $ErrorActionPreference = 'Continue'
    & flutter test integration_test/admin_windows_test.dart -d windows --dart-define-from-file=../config/flutter.local.json
    $taskExit = $LASTEXITCODE
    if ($taskExit -ne 0) { throw 'Falló la prueba nativa de Windows. Revisa el informe local.' }
} finally {
    Pop-Location
    Remove-Item Env:ALUMVID_QA_IDENTIFIER -ErrorAction SilentlyContinue
    Remove-Item Env:ALUMVID_QA_PASSWORD -ErrorAction SilentlyContinue
}
