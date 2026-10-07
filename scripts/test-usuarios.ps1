$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $taskRoot '.env'))) { throw 'Falta .env. Consulta README.md.' }
foreach ($taskLine in Get-Content -LiteralPath (Join-Path $taskRoot '.env')) {
    if ($taskLine -match '^([A-Z_]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
}
$env:DB_URL = "jdbc:postgresql://localhost:$($env:POSTGRES_PORT)/$($env:POSTGRES_DB)"
$env:DB_USER = $env:POSTGRES_USER
$env:DB_PASSWORD = $env:POSTGRES_PASSWORD
Push-Location $taskRoot
try {
    $ErrorActionPreference = 'Continue'
    & .\mvnw.cmd -f services/usuarios-service/pom.xml test
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas del servicio de usuarios.' }
} finally { Pop-Location }
