$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LlamaDir = Join-Path $Root "llama.cpp-new-bin"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-27B-GGUF\Qwen3.6-27B-UD-IQ3_XXS.gguf"

# Fallback to LM Studio cache if project model not found
if (-not (Test-Path $ModelPath)) {
    $ModelPath = "C:\Users\Administrator\.cache\lm-studio\models\unsloth\Qwen3.6-27B-GGUF\Qwen3.6-27B-UD-IQ3_XXS.gguf"
}

# DFlash draft model
$DraftPath = Join-Path $Root "models\Qwen3.6-27B-DFlash-GGUF\Qwen3.6-27B-DFlash-Q8_0.gguf"
if (-not (Test-Path $DraftPath)) {
    $DraftPath = "C:\Users\Administrator\.cache\lm-studio\models\Alittlehammmer\Qwen3.6-27B-DFlash-GGUF\Qwen3.6-27B-DFlash-Q8_0.gguf"
}

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}
if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download with: hf download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-UD-IQ3_XXS.gguf --local-dir models\Qwen3.6-27B-GGUF"
}
if (-not (Test-Path $DraftPath)) {
    throw "Missing DFlash draft at $DraftPath. Download with: hf download Alittlehammmer/Qwen3.6-27B-DFlash-GGUF-llama.cpp Qwen3.6-27B-DFlash-Q8_0.gguf --local-dir models\Qwen3.6-27B-DFlash-GGUF"
}

# â•â•â• Production config for 27B Dense + DFlash + ngram stack â•â•â•
# Based on Reddit research (u/FantasticNature7590, r/LocalLLaMA, July 2026):
#   Full spec stack: draft-dflash,ngram-mod,ngram-map-k4v
#   - DFlash: 2.2-3.7x speedup, ~5.5GB VRAM, drafts 15 tokens at a time
#   - ngram-mod: zero VRAM (host RAM tables), +53% over DFlash alone
#   - ngram-map-k4v: zero VRAM, marginal extra gain on top of mod
#   - Combined: 6.01x on multi-turn coding (321 vs 53.5 tok/s on RTX 6000 PRO)
#   Lossless on MATH-500 (440/500 vs 435/500) and LiveCodeBench
#
# VRAM math on RTX 5060 Ti 16GB:
#   IQ3_XXS target: 11.17 GB
#   DFlash Q8_0 draft: ~5.5 GB (per u/FantasticNature7590 measurement)
#   KV q4_0 at 32K ctx: ~1 GB
#   Total: ~17.7 GB -> TIGHT, may spill slightly to DDR4
#   If overflow becomes a problem, drop -c to 16384 or use ngram-mod only
#
# Context: 32K â€” opencode auto-compacts at 10-15K, 64K reserves wasted VRAM
# Override with LLAMA_CONTEXT env var for special cases

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "32768" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }

$env:GGML_CUDA_NO_PINNED = "1"

$Args = @(
    "-m", $ModelPath,
    "-md", $DraftPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "32768",
    "-np", "1",
    "-fa", "on",
    "--fit", "on",
    "-ngld", "99",
    "--no-mmproj",
    "-ctk", "q4_0",
    "-ctv", "q4_0",
    "--spec-type", "draft-dflash,ngram-mod,ngram-map-k4v",
    "--spec-draft-n-max", "15",
    "--spec-ngram-mod-n-match", "24",
    "--spec-ngram-mod-n-min", "48",
    "--spec-ngram-mod-n-max", "64",
    "--spec-ngram-map-k4v-size-n", "12",
    "--spec-ngram-map-k4v-size-m", "48",
    "--spec-ngram-map-k4v-min-hits", "1",
    "-rea", "off"
)

Write-Host "Starting llama-server (27B IQ3_XXS + DFlash + ngram stack)..."
Write-Host "  Build:    llama.cpp b10054 (CUDA 12.4)"
Write-Host "  Target:   Qwen3.6-27B-UD-IQ3_XXS (11.17GB)"
Write-Host "  Draft:    Qwen3.6-27B-DFlash-Q8_0 (~5.5GB VRAM)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit on, auto GPU/CPU split)"
Write-Host "  Spec:     draft-dflash + ngram-mod + ngram-map-k4v"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=q4_0 V=q4_0"
Write-Host "  Reason:   off (prevents empty content in opencode)"
Write-Host "  Expected: ~6x on multi-turn coding (per Reddit u/FantasticNature7590)"
Write-Host ""

& $ServerExe @Args
