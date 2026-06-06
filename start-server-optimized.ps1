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

# ── Proven config from Reddit 80tok/s guide (12GB VRAM RTX 4070 Super) ──
# Source: r/LocalLLaMA "80 tok/sec and 128K context on 12GB VRAM"
# Adapted for our RTX 5060 Ti 16GB + Windows (no --mlock, no --prio/--poll)
#
# KEY: -fitt 1536 is THE most important parameter. It leaves 1536MB free on GPU
#   for the MTP draft model and KV cache. Fit auto-determines ngl + cpu-moe split.
#   NO manual -ngl or --n-cpu-moe (they crash with fit).
#
# Adaptation notes for Windows/our hardware:
#   - Skipped --mlock (risky on Windows, different behavior than Linux)
#   - Skipped --prio/--poll (caused crash on our system)
#   - Context reduced to 65536 (65K sweet spot on 16GB per njannasch.dev)
#   - Added --no-warmup from proven config (saves startup time)
#   - Added --spec-draft-p-min 0.75 (NVIDIA forum, boosts acceptance)

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$DraftMax     = if ($env:LLAMA_SPEC_DRAFT_N_MAX) { $env:LLAMA_SPEC_DRAFT_N_MAX } else { "2" }
$DraftPMin    = if ($env:LLAMA_SPEC_DRAFT_P_MIN) { $env:LLAMA_SPEC_DRAFT_P_MIN } else { "0.75" }
$SpecType     = if ($env:LLAMA_SPEC_TYPE)    { $env:LLAMA_SPEC_TYPE }    else { "draft-mtp" }
$Parallel     = if ($env:LLAMA_PARALLEL)     { $env:LLAMA_PARALLEL }     else { "1" }
$CacheTypeK   = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "q8_0" }
$CacheTypeV   = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "q8_0" }
$CacheTypeKD  = if ($env:LLAMA_CACHE_TYPE_KD) { $env:LLAMA_CACHE_TYPE_KD } else { "q8_0" }
$CacheTypeVD  = if ($env:LLAMA_CACHE_TYPE_VD) { $env:LLAMA_CACHE_TYPE_VD } else { "q8_0" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$FitTarget    = if ($env:LLAMA_FIT_TARGET)   { $env:LLAMA_FIT_TARGET }   else { "1536M" }
$CtxCheckpoints = if ($env:LLAMA_CTX_CHECKPOINTS) { $env:LLAMA_CTX_CHECKPOINTS } else { "64" }
$BatchSize    = if ($env:LLAMA_BATCH_SIZE)   { $env:LLAMA_BATCH_SIZE }   else { "2048" }
$UbatchSize   = if ($env:LLAMA_UBATCH_SIZE)  { $env:LLAMA_UBATCH_SIZE }  else { "2048" }

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "32768",
    "-np", $Parallel,
    "-fa", "on",
    "-fitt", $FitTarget,
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "-ctkd", $CacheTypeKD,
    "-ctvd", $CacheTypeVD,
    "-ctxcp", $CtxCheckpoints,
    "--no-mmap",
    "--no-warmup",
    "--spec-type", $SpecType
)

if ($SpecType -ne "none") {
    $Args += @("--spec-draft-n-max", $DraftMax)
    $Args += @("--spec-draft-p-min", $DraftPMin)
}

Write-Host "Starting llama-server (Reddit 80tok/s proven config)..."
Write-Host "  Model:    Qwen3.6-35B-A3B-UD-Q4_K_M"
Write-Host "  GPU:      RTX 5060 Ti 16GB (fit auto, target=$FitTarget)"
Write-Host "  Spec:     $SpecType, n-max=$DraftMax, p-min=$DraftPMin"
Write-Host "  Context:  $Context, checkpoints=$CtxCheckpoints"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV, draft K=$CacheTypeKD V=$CacheTypeVD"
Write-Host "  Batch:    $BatchSize / ubatch=$UbatchSize"
Write-Host "  Extras:   no-mmap, no-warmup, jinja"
Write-Host ""

& $ServerExe @Args