$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-27B-GGUF\Qwen3.6-27B-IQ4_XS.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download from Unsloth first."
}

# 27B dense model config - NO MTP (MTP hurts dense models by 42%)
# IQ4_XS (14.38GB) fits in 16GB VRAM with tight KV cache room
# Dense model reads ALL 27B params per token (no MoE sparsity)
# --fit auto: determines GPU/CPU split, no manual overrides (they crash on Windows)
# Expected speed: ~25-27 tok/s on Windows (Linux baseline ~31 tok/s per njannasch)

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$CacheTypeK   = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "q8_0" }
$CacheTypeV   = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "q8_0" }
$CtxCheckpoints = if ($env:LLAMA_CTX_CHECKPOINTS) { $env:LLAMA_CTX_CHECKPOINTS } else { "64" }

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "32768",
    "-np", "1",
    "-fa", "on",
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "-ctxcp", $CtxCheckpoints,
    "--no-mmap"
)

Write-Host "Starting llama-server (27B dense IQ4_XS - NO MTP)..."
Write-Host "  Model:    Qwen3.6-27B-IQ4_XS (14.38GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit auto, no overrides)"
Write-Host "  Spec:     NONE (MTP hurts dense models -42%)"
Write-Host "  Context:  $Context, checkpoints=$CtxCheckpoints"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV"
Write-Host "  Extras:   jinja, no-mmap, flash-attn"
Write-Host "  Expected: ~25-27 tok/s (njannasch Linux 31 tok/s, Windows ~10-15% penalty)"
Write-Host ""

& $ServerExe @Args