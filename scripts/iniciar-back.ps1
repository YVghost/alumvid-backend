param([ValidateSet('Local','External','RailwayCheck')][string]$Mode='Local',[string]$EnvFile)
$taskRoot = Split-Path -Parent $PSScriptRoot
if (!$EnvFile) { $EnvFile = Join-Path $taskRoot $(if ($Mode -eq 'External') { '.env.external' } else { '.env' }) }
if (!(Test-Path -LiteralPath $EnvFile)) { throw "Falta $EnvFile. Copia la plantilla y configura sus credenciales." }
$taskArgs = @('compose','--env-file',$EnvFile)
if ($Mode -eq 'External') { $taskArgs += @('-f','compose.external-db.yaml') }
else { $taskArgs += @('-f','compose.yaml'); if ($Mode -eq 'RailwayCheck') { $taskArgs += @('-f','compose.railway-check.yaml') } }
$taskArgs += @('up','-d','--build','--wait','--wait-timeout','180')
Push-Location $taskRoot
try {
    $ErrorActionPreference = 'Continue'
    & docker @taskArgs
    if ($LASTEXITCODE -ne 0) { throw 'El backend no pudo arrancar; revisa la conexión y los logs.' }
} finally { Pop-Location }
