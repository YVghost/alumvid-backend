# Muestra la IP de esta PC en la red actual y verifica que el backend (gateway :8080) responda.
# Uso: mostrar_ip_servidor.bat  (o)  powershell -File scripts\mostrar-ip-servidor.ps1
$ErrorActionPreference = 'SilentlyContinue'

Write-Host ''
Write-Host '=== Servidor AlumVid (API Gateway, puerto 8080) ===' -ForegroundColor Cyan

$local = $false
try {
    $r = Invoke-RestMethod -Uri 'http://localhost:8080/platform-info' -TimeoutSec 3
    $local = ($r.service -eq 'AlumVid API Gateway')
} catch {}
if ($local) { Write-Host 'Backend: ENCENDIDO en esta PC' -ForegroundColor Green }
else { Write-Host 'Backend: NO responde en localhost:8080 (ejecuta iniciar_todo.bat)' -ForegroundColor Red }

# Interfaces reales con puerta de enlace (Wi-Fi / Ethernet), excluye WSL, Hyper-V, VPN virtuales.
$configs = Get-NetIPConfiguration | Where-Object {
    $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' -and
    $_.InterfaceAlias -notmatch 'vEthernet|WSL|Hyper-V|VirtualBox|VMware|Loopback'
}

if (-not $configs) {
    Write-Host 'No hay ninguna red conectada con puerta de enlace.' -ForegroundColor Yellow
} else {
    Write-Host ''
    Write-Host 'Escribe esta direccion en la app movil (Servidor) si la busqueda automatica falla:' -ForegroundColor White
    foreach ($c in $configs) {
        foreach ($ip in $c.IPv4Address) {
            $url = "http://$($ip.IPAddress):8080"
            $ok = $false
            try {
                $r = Invoke-RestMethod -Uri "$url/platform-info" -TimeoutSec 3
                $ok = ($r.service -eq 'AlumVid API Gateway')
            } catch {}
            $estado = if ($ok) { 'responde' } else { 'no responde por esta IP' }
            $color = if ($ok) { 'Green' } else { 'Yellow' }
            Write-Host ("  {0,-38} [{1}] {2}" -f $url, $c.InterfaceAlias, $estado) -ForegroundColor $color
        }
    }
}

$fw = Get-NetFirewallRule -DisplayName 'AlumVid Gateway 8080' -ErrorAction SilentlyContinue
if (-not $fw) {
    Write-Host ''
    Write-Host 'Si el telefono no conecta, permite el puerto 8080 en el firewall (PowerShell como administrador):' -ForegroundColor Yellow
    Write-Host '  New-NetFirewallRule -DisplayName "AlumVid Gateway 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Private,Public'
}
Write-Host ''
Write-Host 'La PC y el telefono deben estar en la misma red Wi-Fi. En la app: Servidor > Buscar automaticamente.'
Write-Host ''
