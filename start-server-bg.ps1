$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PidFile = Join-Path $Root "llama-server.pid"
$LogFile = Join-Path $Root "llama-server.log"
$ErrFile = Join-Path $Root "llama-server.err.log"

if (Test-Path $PidFile) {
        $ExistingPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue
    if ($ExistingPid) {
        $ExistingProc = Get-Process -Id $ExistingPid -ErrorAction SilentlyContinue
        if ($ExistingProc) {
            Write-Host "llama-server is already running with PID $ExistingPid"
            exit 0
        }
    }
}

$Proc = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $Root "start-server.ps1") `
    -RedirectStandardOutput $LogFile `
    -RedirectStandardError $ErrFile `
    -WindowStyle Hidden `
    -PassThru

$Proc.Id | Set-Content -LiteralPath $PidFile

Write-Host "Started llama-server with PID $($Proc.Id)"
Write-Host "PID file: $PidFile"
Write-Host "Log file: $LogFile"
Write-Host "Err file: $ErrFile"
