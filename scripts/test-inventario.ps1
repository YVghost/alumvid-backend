$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
foreach ($taskLine in Get-Content -LiteralPath (Join-Path $taskRoot '.env')) {
    if ($taskLine -match '^([A-Z_]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
}
$taskDbPort = if ($env:POSTGRES_PORT) { $env:POSTGRES_PORT } else { '5433' }
$env:DB_URL = "jdbc:postgresql://localhost:$taskDbPort/$($env:POSTGRES_DB)"
$env:DB_USER = $env:POSTGRES_USER
$env:DB_PASSWORD = $env:POSTGRES_PASSWORD
Push-Location $taskRoot
try {
    $ErrorActionPreference = 'Continue'
    & .\mvnw.cmd -f services/inventario-service/pom.xml test
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas de inventario.' }
} finally { Pop-Location }
