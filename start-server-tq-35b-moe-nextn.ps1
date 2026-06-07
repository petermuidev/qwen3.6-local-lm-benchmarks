$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "turboquant-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\TurboQuant\Qwen3.6-35B-A3B-UDT-MTP-TQ4_1S.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing TurboQuant server at $ServerExe. Build atomic-llama-cpp-turboquant first — see CONFIG_GUIDE.md"
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download from AtomicChat HuggingFace — see CONFIG_GUIDE.md"
}

# TurboQuant 35B MoE with NextN speculative decoding (+28-36% on 35B MoE)
# Source: https://github.com/AtomicBot-ai/atomic-llama-cpp-turboquant
#
# KEY DIFFERENCES from ik_llama.cpp:
#   - This is a DIFFERENT fork (based on upstream llama.cpp, NOT ik_llama.cpp)
#   - Uses TurboQuant KV cache types (turbo2/3/4) for massive KV compression
#   - Uses --spec-type nextn (not mtp:n_max=1)
#   - -md points to same _MTP.gguf file (shared model, no second mmap)
#   - Pre-built GGUFs from AtomicChat (MTP-aware imatrix, NextN-preserve mask)
#
# turbo3 KV: 3-bit quant, ~4.3x compression, recommended
# TQ4_1S weights: 4-bit TurboQuant weight format
#
# IMPORTANT: NextN uses same GGUF as main model (-md same file)
#   No second mmap needed — the model is shared between main and draft
# IMPORTANT: MTP tensors in AtomicChat GGUFs are Q8_0 (not Q4)
#   Q4 quantized nextn blocks produce garbage //////// output

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$CacheTypeK   = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "turbo3" }
$CacheTypeV   = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "turbo3" }

$Args = @(
    "-m", $ModelPath,
    "-md", $ModelPath,
    "--spec-type", "nextn",
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
    "--cache-ram", "0"
)

Write-Host "Starting TurboQuant server (35B MoE + NextN speculative decoding)..."
Write-Host "  Runtime:  atomic-llama-cpp-turboquant (NOT ik_llama.cpp)"
Write-Host "  Model:    Qwen3.6-35B-A3B-UDT-MTP-TQ4_1S (AtomicChat)"
Write-Host "  Draft:    Same model (-md = same GGUF, shared mmap)"
Write-Host "  Spec:     nextn (NextN speculative decoding)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit auto)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV (~4.3x compression)"
Write-Host "  Cache:    prompt cache DISABLED (--cache-ram 0)"
Write-Host "  Extras:   jinja, no-mmap, flash-attn"
Write-Host "  Expected: +28-36% over baseline (AtomicBot benchmarks)"
Write-Host ""

& $ServerExe @Args