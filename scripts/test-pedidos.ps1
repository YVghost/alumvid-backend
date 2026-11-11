$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    $ErrorActionPreference = 'Continue'
    & .\mvnw.cmd -f services/pedidos-service/pom.xml test
    $taskExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($taskExit -ne 0) { throw 'Fallaron las pruebas aisladas de pedidos. Revisa Docker y Maven.' }
} finally { Pop-Location }
