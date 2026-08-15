$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
# IMPORTANT: use llama.cpp-b9360-cuda12, NOT llama.cpp-new-bin (b10054).
# The b10054 Windows CUDA prebuild silently disables spec decoding at compile
# time (--spec-type ngram-mod is accepted but no spec context initializes,
# "speculative.types": "none" in /props, no draft_n in timings).
# b9360 correctly initializes ngram-mod: boot log shows
#   "common_speculative_impl_ngram_mod: adding speculative implementation 'ngram-mod'"
#   "speculative decoding context initialized"
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-27B-GGUF\Qwen3.6-27B-UD-IQ3_XXS.gguf"

# Fallback to LM Studio cache if project model not found
if (-not (Test-Path $ModelPath)) {
    $ModelPath = "C:\Users\Administrator\.cache\lm-studio\models\unsloth\Qwen3.6-27B-GGUF\Qwen3.6-27B-UD-IQ3_XXS.gguf"
}

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}
if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download with: hf download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-UD-IQ3_XXS.gguf --local-dir models\Qwen3.6-27B-GGUF"
}

# â•â•â• Production config for 27B Dense + ngram-mod ONLY (no DFlash) â•â•â•
# WHY NO DFLASH:
#   DFlash draft model = ~5.5GB VRAM. On 16GB RTX 5060 Ti:
#     IQ3_XXS (11.17GB) + DFlash (5.5GB) + KV q4_0 (~1GB) = 17.7GB -> overflows
#     --fit on spills target layers to DDR4 -> 13 t/s (WORSE than baseline 26 t/s)
#   DFlash only wins on 24GB+ cards where the draft fits without spilling target.
#
# WHY NGRAM-MOD ONLY:
#   ngram-mod stores lookup tables in HOST RAM â€” zero VRAM cost.
#   Target stays fully on GPU (-ngl 99) = baseline ~26 tok/s single-turn.
#   On multi-turn sessions (coding, editing own code), n-gram cache fills and
#   drafts tokens from memory -> 1.5-3x speedup per Reddit u/FantasticNature7590.
#   The n-gram advantage GROWS with session length (more context = more to copy).
#   Lossless on MATH-500 and LiveCodeBench per Reddit research.
#
# BUILD: llama.cpp b9360 (CUDA 12.4) â€” verified to activate ngram-mod at boot
# NOTE: b10054 Windows prebuild silently drops spec decoding; do NOT use it.
# b9360 boot log confirms: "speculative decoding context initialized" with
# ngram-mod table = 16 MB in host RAM (zero VRAM cost).
#
# COMPARISON TO LEGACY start-server-27b.ps1:
#   Legacy uses llama.cpp b9360 + IQ3_M (12GB) + MTP draft (300MB) = ~28 t/s
#   This uses llama.cpp b10054 + IQ3_XXS (11.17GB) + ngram-mod (0 VRAM) = ~26 t/s baseline
#   Single-turn: roughly equivalent (maybe slightly slower due to IQ3_XXS vs IQ3_M)
#   Multi-turn: this should WIN as n-gram cache fills (MTP can't copy from context)
#
# VRAM math on RTX 5060 Ti 16GB:
#   IQ3_XXS target: 11.17 GB
#   KV q4_0 at 32K ctx: ~1 GB
#   ngram-mod tables: 0 GB (host RAM)
#   Total: ~12.2 GB -> fits comfortably, all target layers on GPU

# Context: 32K default â€” verified safe on 16GB VRAM (12939 MiB used, 3.1GB margin).
# 48K+ causes DDR4 offload (VRAM hits 15.9GB, prompt processing collapses to <1 tok/s).
# opencode auto-compacts at 10-15K anyway, so 32K is the sweet spot.
# Override with LLAMA_CONTEXT env var (e.g. 49152 for one-shot long-context tests).
$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "32768" }
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
    "-n", "32768",
    "-np", "1",
    "-ngl", "99",
    "-fa", "on",
    "--no-mmproj",
    "-ctk", "q4_0",
    "-ctv", "q4_0",
    "--spec-type", "ngram-mod",
    "--spec-ngram-mod-n-match", "24",
    "--spec-ngram-mod-n-min", "48",
    "--spec-ngram-mod-n-max", "64",
    "-rea", "off"
)

Write-Host "Starting llama-server (27B IQ3_XXS + ngram-mod only, no DFlash)..."
Write-Host "  Build:    llama.cpp b9360 (CUDA 12.4, ngram-mod verified active)"
Write-Host "  Target:   Qwen3.6-27B-UD-IQ3_XXS (11.17GB, all on GPU)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (-ngl 99, NO --fit, NO CPU offload)"
Write-Host "  Spec:     ngram-mod ONLY (n_max=64, n_min=48, ngram_size_n=24)"
Write-Host "  VRAM:     ~12.9GB at 32K ctx (fits 16GB with 3.1GB margin)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=q4_0 V=q4_0"
Write-Host "  Reason:   off (prevents empty content in opencode)"
Write-Host "  Baseline: ~26 tok/s single-turn (same as legacy 27B)"
Write-Host "  Multi-turn: ngram-mod kicks in as cache fills (free speedup)"
Write-Host ""

& $ServerExe @Args
