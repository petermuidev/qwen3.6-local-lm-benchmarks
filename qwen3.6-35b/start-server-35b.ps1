$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-35B-A3B-MTP-GGUF\Qwen3.6-35B-A3B-UD-Q4_K_S.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}
if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath"
}

# ═══ Production config for 35B MoE on RTX 5060 Ti 16GB ═══
# Benchmarked: 53.56 tok/s avg (short), 57.49 tok/s (multi-turn), 44.74 tok/s (long 500tok)
# 5/5 benchmark tasks passed, 64k context stable
#
# Critical flags that were missing in old config:
#   --fit on       — auto GPU/CPU tensor split (was MISSING, biggest bottleneck)
#   --kv-unified   — unified KV cache saves VRAM
#   --no-mmproj    — skip multimodal projector, saves VRAM
#
# Flags removed from old config that were harmful:
#   --no-mmap      — forced full RAM load, hurt MoE expert paging
#   --cache-ram 0  — disabled prompt caching unnecessarily
#
# KV cache: q8_0/q8_0 is fastest for generation (lower quants hurt MoE)
# Speculative: draft-mtp + ngram-mod gives +16% over baseline

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "64000" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }

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
    "--fit", "on",
    "--kv-unified",
    "--no-mmproj",
    "-ctk", "q8_0",
    "-ctv", "q8_0",
    "--spec-type", "draft-mtp,ngram-mod",
    "--spec-draft-n-max", "2",
    "--spec-ngram-mod-n-match", "40",
    "--spec-ngram-mod-n-min", "0",
    "--spec-ngram-mod-n-max", "16",
    "-rea", "off"
)

Write-Host "Starting llama-server (35B MoE production config)..."
Write-Host "  Model:    Qwen3.6-35B-A3B-UD-Q4_K_S (19.9GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit on, --kv-unified)"
Write-Host "  Spec:     draft-mtp + ngram-mod (n-max=2, ngram match=40)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=q8_0 V=q8_0 (fastest for MoE generation)"
Write-Host "  Bench:    53.56 t/s avg, 57.49 t/s multi-turn, 44.74 t/s long"
Write-Host ""

& $ServerExe @Args
