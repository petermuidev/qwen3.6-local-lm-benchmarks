$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PidFile = Join-Path $Root "llama-server.pid"

if (-not (Test-Path $PidFile)) {
    Write-Host "No PID file found."
    exit 0
}

$ServerPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue
if (-not $ServerPid) {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Write-Host "PID file was empty."
    exit 0
}

$Proc = Get-Process -Id $ServerPid -ErrorAction SilentlyContinue
if ($Proc) {
    Stop-Process -Id $ServerPid -Force
    Write-Host "Stopped llama-server PID $ServerPid"
} else {
    Write-Host "Process $ServerPid was not running"
}

Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
