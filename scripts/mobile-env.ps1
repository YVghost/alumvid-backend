param(
    [string]$FlutterSdk = "$env:USERPROFILE\dev\sdk\flutter",
    [string]$AndroidSdk = "$env:LOCALAPPDATA\Android\Sdk",
    [string]$JavaSdk = "$env:USERPROFILE\dev\jdk-21"
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath "$FlutterSdk\bin\flutter.bat")) { throw "No se encontro Flutter en $FlutterSdk. Instala el SDK o indica -FlutterSdk." }
if (!(Test-Path -LiteralPath "$JavaSdk\bin\java.exe")) { throw "No se encontro JDK 21 en $JavaSdk. Indica -JavaSdk." }
$env:FLUTTER_ROOT = $FlutterSdk
$env:JAVA_HOME = $JavaSdk
$env:ANDROID_HOME = $AndroidSdk
$env:PATH = "$FlutterSdk\bin;$JavaSdk\bin;$AndroidSdk\platform-tools;$AndroidSdk\emulator;$AndroidSdk\cmdline-tools\latest\bin;$env:PATH"
Write-Host 'Entorno Flutter/Android activado para esta terminal.' -ForegroundColor Green
