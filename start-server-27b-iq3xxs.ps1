$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-27B-GGUF\Qwen3.6-27B-UD-IQ3_XXS.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download from Unsloth first."
}

# 27B dense IQ3_XXS (11.17GB) - fits entirely in 16GB VRAM with KV cache room
# NO MTP (MTP hurts dense models by 42%)
# njannasch gets 31 tok/s on Linux RTX 5060 Ti 16GB, expect ~26-28 tok/s on Windows
# q4_0 KV cache: lossless on Qwen hybrid models, saves VRAM vs q8_0

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$CacheTypeK   = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "q4_0" }
$CacheTypeV   = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "q4_0" }

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
    "--no-mmap",
    "--no-warmup",
    "--cache-ram", "0"
)

Write-Host "Starting llama-server (27B dense IQ3_XXS - NO MTP)..."
Write-Host "  Model:    Qwen3.6-27B-UD-IQ3_XXS (11.17GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit auto, no overrides)"
Write-Host "  Spec:     NONE (MTP hurts dense models -42%)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV (lossless on Qwen hybrid)"
Write-Host "  Cache:    prompt cache DISABLED (--cache-ram 0)"
Write-Host "  Extras:   jinja, no-mmap, no-warmup, flash-attn"
Write-Host ""

& $ServerExe @Args