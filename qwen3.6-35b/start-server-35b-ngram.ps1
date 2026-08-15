$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LlamaDir = Join-Path $Root "llama.cpp-new-bin"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-35B-A3B-MTP-GGUF\Qwen3.6-35B-A3B-UD-Q4_K_S.gguf"

# Fallback to LM Studio cache if project model not found
if (-not (Test-Path $ModelPath)) {
    $ModelPath = "C:\Users\Administrator\.cache\lm-studio\models\lmstudio-community\Qwen3.6-35B-A3B-GGUF\Qwen3.6-35B-A3B-Q4_K_M.gguf"
}

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}
if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath"
}

# â•â•â• Production config for 35B MoE + ngram-mod on new llama.cpp build â•â•â•
# Based on Reddit research (July 2026):
#   - llama.cpp PR #25545 improved CPU-offload path 3x (2->7 t/s on 98GB model)
#     This directly helps our --n-cpu-moe 20 config on DDR4-starved hardware
#   - ngram-mod is FREE on VRAM (tables in host RAM), +50% on multi-turn coding
#   - DFlash skipped: 5.5GB draft + 19.7GB target > 16GB VRAM
#
# Keeps the proven July 2026 config (--n-cpu-moe 20, q4_0 KV, -ngl 99)
# with the new build + ngram-mod on top
#
# Benchmarked predecessor: ~43 tok/s at 64K ctx (ik_llama bec81cf)
# Expected with new build + ngram-mod: higher

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }

$env:GGML_CUDA_NO_PINNED = "1"

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "4096",
    "-np", "1",
    "-ngl", "99",
    "-fa", "on",
    "--n-cpu-moe", "20",
    "-ctk", "q4_0",
    "-ctv", "q4_0",
    "--spec-type", "ngram-mod",
    "--spec-ngram-mod-n-match", "24",
    "--spec-ngram-mod-n-min", "48",
    "--spec-ngram-mod-n-max", "64",
    "-rea", "off"
)

Write-Host "Starting llama-server (35B MoE + ngram-mod, new build)..."
Write-Host "  Build:    llama.cpp b10054 (CUDA 12.4, PR #25545 CPU-offload gains)"
Write-Host "  Model:    Qwen3.6-35B-A3B (19.7GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (-ngl 99, --n-cpu-moe 20)"
Write-Host "  Spec:     ngram-mod (n_max=64, n_min=48, ngram_size_n=24)"
Write-Host "  KV:       q4_0/q4_0 (compressed, fits 64K in VRAM)"
Write-Host "  Context:  $Context"
Write-Host "  Reason:   off"
Write-Host "  Baseline: ~43 tok/s @ 64K (predecessor, ik_llama bec81cf)"
Write-Host ""

& $ServerExe @Args
