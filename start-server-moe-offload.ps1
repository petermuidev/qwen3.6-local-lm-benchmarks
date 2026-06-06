$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-35B-A3B-MTP-GGUF\Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe. Run .\setup.ps1 first."
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Run .\setup.ps1 first."
}

# MoE CPU offload config (HuggingFace guide approach)
# --fit OFF to prevent auto-fit conflicts with manual overrides
# -ngl 999: put all layers on GPU declaration (experts overridden by --cpu-moe)
# --cpu-moe: routed experts go to CPU, everything else stays on GPU
# This keeps attention + dense FFN + shared expert on GPU (always active)
# Routed experts on CPU (only 8/256 active per token, ~3B per forward pass)

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$BatchSize    = if ($env:LLAMA_BATCH_SIZE)   { $env:LLAMA_BATCH_SIZE }   else { "4096" }
$UbatchSize   = if ($env:LLAMA_UBATCH_SIZE)  { $env:LLAMA_UBATCH_SIZE }  else { "4096" }
$CacheTypeK   = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "q8_0" }
$CacheTypeV   = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "q8_0" }

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "32768",
    "-np", "1",
    "-ngl", "999",
    "--cpu-moe",
    "-fa", "on",
    "-b", $BatchSize,
    "-ub", $UbatchSize,
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "-ctxcp", "64",
    "--no-mmap",
    "--no-warmup",
    "--fit", "off"
)

Write-Host "Starting llama-server (MoE CPU offload config)..."
Write-Host "  Model:    Qwen3.6-35B-A3B-UD-Q4_K_M"
Write-Host "  GPU:      RTX 5060 Ti 16GB (MoE offload: attn+shared on GPU, routed experts on CPU)"
Write-Host "  Spec:     NONE (baseline, no MTP)"
Write-Host "  Context:  $Context, checkpoints=64"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV"
Write-Host "  Batch:    $BatchSize / ubatch=$UbatchSize"
Write-Host "  Extras:   no-mmap, no-warmup, jinja, flash-attn"
Write-Host "  CRITICAL: --fit OFF, -ngl 999, --cpu-moe (explicit MoE split)"
Write-Host ""

& $ServerExe @Args