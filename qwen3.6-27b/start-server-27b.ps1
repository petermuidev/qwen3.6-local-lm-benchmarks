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

# Production config for 27B Dense on RTX 5060 Ti 16GB
# Benchmarked: 28 t/s short ctx, stable 15-23 t/s in opencode multi-turn
# 4/4 benchmark tasks passed, 64k context
#
# Why IQ3_M not IQ4_XS:
#   IQ4_XS-MTP (15GB) + f16 draft KV + 64k ctx = overflows 16GB VRAM
#   IQ3_M-MTP (12GB) leaves 4GB for KV + draft cache = fits VRAM
#
# Why draft-max=1:
#   draft-max=3 was breaking tool call JSON in opencode (speculative tokens
#   corrupt structured output when a draft is rejected mid-JSON)
#   draft-max=1 is safer — only 1 speculative token, less chance of corruption
#   Acceptance rate ~87% on our hardware
#
# Why -rea off:
#   Qwen 3.6 thinking mode returns empty content — breaks opencode
#
# Speed at different context sizes (raw API, no client-side compact):
#   <1K: 28 t/s | 10K: ~15 t/s | 15K+: ~10 t/s
#   opencode auto-compacts, so real-world ~15-23 t/s stable

# Context: 32K not 64K — opencode compacts at ~10-15K anyway.
# 64K reserves 4.6GB KV VRAM (wasted), pushes layers to CPU, DDR4 kills speed.
# 32K reserves ~2.3GB KV, model stays mostly on GPU.
$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "32000" }
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

Write-Host "Starting llama-server (27B IQ3_M + MTP)..."
Write-Host "  Model:    Qwen3.6-27B-IQ3_M-mtp (12GB, fits 16GB VRAM)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (-ngl 99, all GPU)"
Write-Host "  Spec:     draft-mtp draft-max=1 (safer for tool call JSON)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=q4_0 V=q4_0"
Write-Host "  Reason:   off (prevents empty content in opencode)"
Write-Host "  Speed:    ~28 t/s short, ~15-23 t/s opencode multi-turn"
Write-Host ""

& $ServerExe @Args
