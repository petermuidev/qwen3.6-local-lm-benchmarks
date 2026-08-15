$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-27B-MTP-GGUF\Qwen3.6-27B-IQ3_M-mtp.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}
if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download with: hf download froggeric/Qwen3.6-27B-MTP-GGUF Qwen3.6-27B-IQ3_M-mtp.gguf --local-dir models\Qwen3.6-27B-MTP-GGUF"
}

# 27B Dense 60K context config for complex multi-step tasks
# Trades speed (~15-20 t/s) for more context room (less compaction)
# Use start-server-27b.ps1 (32K) for speed-critical tasks
#
# Why 60K not 64K:
#   64K over-reserves KV, 60K leaves just enough headroom
#   Same model, same flags, just bigger context window

# Context: 60K â€” trades speed for context room.
# 32K = ~30 t/s (model on GPU). 60K = ~15-20 t/s (some layers offload to CPU).
$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "60000" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--chat-template-file", (Join-Path $Root "models\Qwen3.6-27B-MTP-GGUF\templates\chat_template.jinja"),
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "32768",
    "-np", "1",
    "-ngl", "99",
    "-fa", "on",
    "--kv-unified",
    "--no-mmproj",
    "-ctk", "q4_0",
    "-ctv", "q4_0",
    "--spec-type", "draft-mtp",
    "--spec-draft-n-max", "1",
    "-rea", "off"
)

Write-Host "Starting llama-server (27B IQ3_M + MTP, 60K context)..."
Write-Host "  Model:    Qwen3.6-27B-IQ3_M-mtp (12GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (-ngl 99)"
Write-Host "  Spec:     draft-mtp draft-max=1"
Write-Host "  Context:  $Context (trades speed for context room)"
Write-Host "  KV cache: K=q4_0 V=q4_0"
Write-Host "  Reason:   off (prevents empty content in opencode)"
Write-Host "  Speed:    ~15-20 t/s (some CPU offload at 60K ctx)"
Write-Host ""

& $ServerExe @Args
