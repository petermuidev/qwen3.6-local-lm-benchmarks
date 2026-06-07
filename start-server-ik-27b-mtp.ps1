$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "ik-llama.cpp-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"

# Requires MTP-enabled GGUF (has nextn prediction heads preserved)
# Download from: Radamanthys11/Qwen3.6-27B-MTP-Q8_0-GGUF
# Or create your own using ik_llama.cpp qwen-35-mtp-gguf branch
# Q8_0 MTP GGUF is ~15.3GB — tight fit on 16GB VRAM but works with q4_0 KV
$ModelPath = Join-Path $Root "models\Qwen3.6-27B-MTP-GGUF\Qwen3.6-27B-MTP-Q8_0.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing ik_llama.cpp server at $ServerExe. Build ik_llama.cpp first — see CONFIG_GUIDE.md"
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download MTP GGUF from Radamanthys11 first — see CONFIG_GUIDE.md"
}

# ik_llama.cpp 27B dense + MTP (EXPERIMENTAL — test before trusting)
#
# ik_llama.cpp PR #1698 added MTP for Qwen 3.6 dense models (27B only, NOT 35B MoE)
# Evidence (2x RTX 3090): 23.3→29.6 tok/s (+27%) layer mode, 36.8→41.6 (+13%) graph mode
# 82-87% accept rate with draft-max=1
#
# WARNING: Previous finding was "MTP hurts dense by 42%" — that was on
#   upstream llama.cpp with IQ3_XXS partial offload. This config uses:
#   1. ik_llama.cpp (better MTP implementation)
#   2. Q8_0 MTP GGUF (full MTP heads, not Q4 quantized which produces garbage)
#   3. draft-max=1 only (draft-max=2 gives 51% accept, diminishing returns)
#
# CRITICAL: Use --spec-type mtp:n_max=1,p_min=0.0 (canonical ik_llama.cpp flag)
#   NOT legacy --spec-type draft-mtp
# CRITICAL: MTP nextn blocks must be Q8_0 — Q4 quantized nextn produces //////// garbage

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$SpecType     = if ($env:LLAMA_SPEC_TYPE)    { $env:LLAMA_SPEC_TYPE }    else { "mtp:n_max=1,p_min=0.0" }
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
    "--spec-type", $SpecType,
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "--no-mmap",
    "--no-warmup",
    "--cache-ram", "0"
)

Write-Host "Starting ik_llama.cpp server (27B dense + MTP EXPERIMENTAL)..."
Write-Host "  Runtime:  ik_llama.cpp (MTP for dense models, PR #1698)"
Write-Host "  Model:    Qwen3.6-27B-MTP-Q8_0 (~15.3GB, MTP heads preserved)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit auto, tight fit with q4_0 KV)"
Write-Host "  Spec:     $SpecType"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV"
Write-Host "  Cache:    prompt cache DISABLED (--cache-ram 0)"
Write-Host "  Extras:   no-mmap, no-warmup, jinja, flash-attn"
Write-Host "  Expected: ~30-35 tok/s (EXPERIMENTAL — benchmark to verify)"
Write-Host "  WARNING:  Previous MTP finding was -42%. This may differ with ik_llama.cpp."
Write-Host ""

& $ServerExe @Args