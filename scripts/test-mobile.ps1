param([switch]$BuildApk)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\mobile-env.ps1"
function Invoke-TaskFlutter {
    param([string[]]$TaskArguments)
    $taskPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & flutter @TaskArguments
        $taskExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $taskPreference }
    if ($taskExit -ne 0) { throw "Fallo flutter $($TaskArguments -join ' ') (codigo $taskExit)." }
}
Push-Location "$taskRoot\alumvid_mobile"
try {
    Invoke-TaskFlutter -TaskArguments @('pub','get')
    Invoke-TaskFlutter -TaskArguments @('analyze')
    Invoke-TaskFlutter -TaskArguments @('test')
    if ($BuildApk) { Invoke-TaskFlutter -TaskArguments @('build','apk','--debug') }
} finally { Pop-Location }
