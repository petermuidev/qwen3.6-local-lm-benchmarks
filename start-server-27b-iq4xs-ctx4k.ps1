$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-27B-GGUF\Qwen3.6-27B-IQ4_XS.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath"
}

# 27B dense IQ4_XS with reduced context (4096) to fit in 16GB VRAM
# IQ4_XS (14.38GB) barely fits in 16GB - KV cache for 65536 context exceeds VRAM
# Reducing context to 4096 gives more KV cache headroom

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "4096" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$CacheTypeK   = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "q8_0" }
$CacheTypeV   = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "q8_0" }

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "2048",
    "-np", "1",
    "-fa", "on",
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "--no-mmap"
)

Write-Host "Starting llama-server (27B dense IQ4_XS - ctx=4096)..."
Write-Host "  Model:    Qwen3.6-27B-IQ4_XS (14.38GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit auto, no overrides)"
Write-Host "  Spec:     NONE"
Write-Host "  Context:  $Context (reduced from 65536 for VRAM fit)"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV"
Write-Host "  Extras:   jinja, no-mmap, flash-attn"
Write-Host ""

& $ServerExe @Args