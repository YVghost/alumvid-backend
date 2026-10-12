$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Write-Host "Iniciando suite de verificacion integral de microservicios AlumVid..." -ForegroundColor Cyan

Push-Location $taskRoot
try {
    Write-Host "`n=== 1/3 Compilando y probando usuarios-service ===" -ForegroundColor Yellow
    & .\scripts\test-usuarios.ps1

    Write-Host "`n=== 2/3 Compilando y probando inventario-service ===" -ForegroundColor Yellow
    & .\scripts\test-inventario.ps1

    Write-Host "`n=== 3/3 Compilando y probando logistica-service ===" -ForegroundColor Yellow
    & .\scripts\test-logistica.ps1

    Write-Host "`n¡TODAS LAS PRUEBAS DE MICROSERVICIOS PASARON EXITOSAMENTE!" -ForegroundColor Green
} finally { Pop-Location }
