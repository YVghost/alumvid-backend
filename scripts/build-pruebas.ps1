param([ValidateSet('Local','Railway')][string]$DefaultEnvironment='Local',[string]$RailwayUrl,[string]$LocalUrl,[int]$BuildNumber=2)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'mobile-env.ps1')
$taskEnv = @{}
if (Test-Path (Join-Path $taskRoot '.env')) {
    foreach ($taskLine in Get-Content -LiteralPath (Join-Path $taskRoot '.env')) {
        if ($taskLine -match '^([A-Z_]+)=(.*)$') { $taskEnv[$Matches[1]]=$Matches[2].Trim().Trim('"').Trim("'") }
    }
}
if (!$RailwayUrl) { $RailwayUrl=$taskEnv['RAILWAY_API_URL'] }
if (!$LocalUrl) { $LocalUrl=$taskEnv['LOCAL_API_URL'] }
if (!$LocalUrl) { $LocalUrl='http://localhost:8080' }
function Get-TaskOrigin([string]$Value) {
    $taskUri = $null
    if (![Uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$taskUri) -or $taskUri.Scheme -notin @('http','https') -or $taskUri.UserInfo -or $taskUri.Query -or $taskUri.Fragment -or $taskUri.AbsolutePath -notin @('/','/api/v1','/api/v1/')) { throw 'La dirección del servidor no es válida.' }
    return $taskUri.GetLeftPart([UriPartial]::Authority)
}
$LocalUrl=Get-TaskOrigin $LocalUrl
if ($RailwayUrl) { $RailwayUrl=Get-TaskOrigin $RailwayUrl; if (!$RailwayUrl.StartsWith('https://')) { throw 'Railway debe usar HTTPS.' } }
if ($DefaultEnvironment -eq 'Railway' -and !$RailwayUrl) { throw 'Configura RAILWAY_API_URL o pasa -RailwayUrl.' }
$taskDefines = @{LOCAL_API_URL=$LocalUrl; RAILWAY_API_URL=$(if ($RailwayUrl) {$RailwayUrl} else {''}); API_HOST=$(if ($DefaultEnvironment -eq 'Railway') {$RailwayUrl} else {$LocalUrl})}
if ($DefaultEnvironment -eq 'Railway') { $taskDefines['API_BASE_URL']=$RailwayUrl+'/api/v1' }
$taskClientConfig = Join-Path $taskRoot 'config\flutter.local.json'
if (Test-Path $taskClientConfig) {
    $taskClientValues = Get-Content -LiteralPath $taskClientConfig -Raw | ConvertFrom-Json
    if ($taskClientValues.GOOGLE_MAPS_API_KEY) { $taskDefines['GOOGLE_MAPS_API_KEY']=$taskClientValues.GOOGLE_MAPS_API_KEY }
}
New-Item -Path (Join-Path $taskRoot '.cache') -ItemType Directory -Force | Out-Null
$taskDefineFile=Join-Path $taskRoot '.cache\apps-build.local.json'
[IO.File]::WriteAllText($taskDefineFile,($taskDefines | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
$taskBackup=Join-Path $taskRoot ('.cache\binarios-antes-railway-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -Path $taskBackup -ItemType Directory -Force | Out-Null
foreach ($taskOld in @('entrega-pruebas\android\AlumVid.apk','entrega-pruebas\AlumVidAdmin-Windows.zip')) {
    $taskOldPath=Join-Path $taskRoot $taskOld
    if (Test-Path $taskOldPath) { Copy-Item -LiteralPath $taskOldPath -Destination $taskBackup }
}
function Invoke-TaskFlutter([string[]]$Arguments) {
    $taskPreference=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try { & flutter @Arguments; $taskCode=$LASTEXITCODE } finally { $ErrorActionPreference=$taskPreference }
    if ($taskCode -ne 0) { throw 'Falló la compilación Flutter; no se reemplazaron los paquetes de entrega.' }
}
Push-Location (Join-Path $taskRoot 'alumvid_mobile')
try { Invoke-TaskFlutter @('build','apk','--release',"--build-number=$BuildNumber","--dart-define-from-file=$taskDefineFile") } finally { Pop-Location }
Push-Location (Join-Path $taskRoot 'alumvid_admin_desktop')
try { Invoke-TaskFlutter @('build','windows','--release',"--build-number=$BuildNumber","--dart-define-from-file=$taskDefineFile") } finally { Pop-Location }
$taskAndroid=Join-Path $taskRoot 'entrega-pruebas\android'
$taskWindows=Join-Path $taskRoot 'entrega-pruebas\windows\AlumVidAdmin'
New-Item -ItemType Directory -Path $taskAndroid,$taskWindows -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot 'alumvid_mobile\build\app\outputs\flutter-apk\app-release.apk') -Destination (Join-Path $taskAndroid 'AlumVid.apk') -Force
Copy-Item -Path (Join-Path $taskRoot 'alumvid_admin_desktop\build\windows\x64\runner\Release\*') -Destination $taskWindows -Recurse -Force
Compress-Archive -Path $taskWindows -DestinationPath (Join-Path $taskRoot 'entrega-pruebas\AlumVidAdmin-Windows.zip') -Force
Write-Host 'APK y Windows actualizados en entrega-pruebas. Las credenciales y el respaldo anterior permanecen locales.'
