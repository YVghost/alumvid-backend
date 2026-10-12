$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $taskRoot '.env')) {
    foreach ($taskLine in Get-Content -LiteralPath (Join-Path $taskRoot '.env')) {
        if ($taskLine -match '^([A-Z_]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
    }
}
$dbPort = if ($env:DB_PORT) { $env:DB_PORT } else { '5433' }
$dbName = if ($env:DB_NAME) { $env:DB_NAME } else { 'alumvid_db' }
$env:DB_URL = "jdbc:postgresql://localhost:$dbPort/$dbName"
$env:DB_USER = if ($env:DB_USER) { $env:DB_USER } else { 'alumvid_admin' }
$env:DB_PASSWORD = if ($env:DB_PASSWORD) { $env:DB_PASSWORD } else { 'alumvid_secure_2026' }

Push-Location $taskRoot
try {
    $ErrorActionPreference = 'Continue'
    & .\mvnw.cmd -f services/usuarios-service/pom.xml test
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas del servicio de usuarios.' }
} finally { Pop-Location }
