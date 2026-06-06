$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"

# UD-Q4_K_S (19.9GB) - smaller than Q4_K_M (21.1GB), less CPU offload needed
# Still includes MTP heads for speculative decoding capability
$ModelPath = Join-Path $Root "models\Qwen3.6-35B-A3B-MTP-GGUF\Qwen3.6-35B-A3B-UD-Q4_K_S.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe. Run .\setup.ps1 first."
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download from Unsloth first."
}

# Research-backed config for RTX 5060 Ti 16GB + DDR4 + Windows
# --fit auto: proven best at 36.1 tok/s baseline (better than manual MoE offload at 23.1)
# No manual -ngl or --cpu-moe (they conflict with --fit and crash on Windows)
# MTP enabled with n-max=2 (Unsloth recommended, no determinism bug)

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$SpecType     = if ($env:LLAMA_SPEC_TYPE)    { $env:LLAMA_SPEC_TYPE }    else { "draft-mtp" }
$DraftMax     = if ($env:LLAMA_SPEC_DRAFT_N_MAX) { $env:LLAMA_SPEC_DRAFT_N_MAX } else { "2" }
$DraftPMin    = if ($env:LLAMA_SPEC_DRAFT_P_MIN) { $env:LLAMA_SPEC_DRAFT_P_MIN } else { "0.75" }
$Parallel     = if ($env:LLAMA_PARALLEL)     { $env:LLAMA_PARALLEL }     else { "1" }
$CacheTypeK   = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "q8_0" }
$CacheTypeV   = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "q8_0" }
$CacheTypeKD  = if ($env:LLAMA_CACHE_TYPE_KD) { $env:LLAMA_CACHE_TYPE_KD } else { "q8_0" }
$CacheTypeVD  = if ($env:LLAMA_CACHE_TYPE_VD) { $env:LLAMA_CACHE_TYPE_VD } else { "q8_0" }
$CtxCheckpoints = if ($env:LLAMA_CTX_CHECKPOINTS) { $env:LLAMA_CTX_CHECKPOINTS } else { "64" }

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
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "-ctkd", $CacheTypeKD,
    "-ctvd", $CacheTypeVD,
    "-ctxcp", $CtxCheckpoints,
    "--no-mmap",
    "--no-warmup",
    "--cache-ram", "0",
    "--spec-type", $SpecType
)

if ($SpecType -ne "none") {
    $Args += @("--spec-draft-n-max", $DraftMax)
    $Args += @("--spec-draft-p-min", $DraftPMin)
}

Write-Host "Starting llama-server (Unsloth UD-Q4_K_S + MTP)..."
Write-Host "  Model:    Qwen3.6-35B-A3B-UD-Q4_K_S (Unsloth, 19.9GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit auto, no overrides)"
Write-Host "  Spec:     $SpecType, n-max=$DraftMax, p-min=$DraftPMin"
Write-Host "  Context:  $Context, checkpoints=$CtxCheckpoints"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV, draft K=$CacheTypeKD V=$CacheTypeVD"
Write-Host "  Cache:    prompt cache DISABLED (--cache-ram 0)"
Write-Host "  Extras:   no-mmap, no-warmup, jinja, flash-attn"
Write-Host ""

& $ServerExe @Args