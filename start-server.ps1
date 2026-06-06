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

$Context = if ($env:LLAMA_CONTEXT) { $env:LLAMA_CONTEXT } else { "120000" }
$Port = if ($env:LLAMA_PORT) { $env:LLAMA_PORT } else { "8080" }
$HostAddr = if ($env:LLAMA_HOST) { $env:LLAMA_HOST } else { "127.0.0.1" }
$GpuLayers = if ($env:LLAMA_GPU_LAYERS) { $env:LLAMA_GPU_LAYERS } else { "26" }
$DraftGpuLayers = $env:LLAMA_DRAFT_GPU_LAYERS
$DraftMax = if ($env:LLAMA_SPEC_DRAFT_N_MAX) { $env:LLAMA_SPEC_DRAFT_N_MAX } else { "3" }
$Parallel = if ($env:LLAMA_PARALLEL) { $env:LLAMA_PARALLEL } else { "1" }
$CacheTypeK = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "q8_0" }
$CacheTypeV = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "q8_0" }
$Threads = if ($env:LLAMA_THREADS) { $env:LLAMA_THREADS } else { "16" }
$CpuMoe = if ($env:LLAMA_CPU_MOE) { $env:LLAMA_CPU_MOE } else { "16" }
$FitTarget = if ($env:LLAMA_FIT_TARGET) { $env:LLAMA_FIT_TARGET } else { "512M" }
$SpecType = if ($env:LLAMA_SPEC_TYPE) { $env:LLAMA_SPEC_TYPE } else { "draft-mtp" }

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-np", $Parallel,
    "--n-cpu-moe", $CpuMoe,
    "--no-mmap",
    "--fit", "on",
    "--fit-ctx", $Context,
    "--fit-target", $FitTarget,
    "-fa", "on",
    "--cache-type-k", $CacheTypeK,
    "--cache-type-v", $CacheTypeV,
    "--spec-type", $SpecType
)

if ($SpecType -ne "none") {
    $Args += @("--spec-draft-n-max", $DraftMax)
}

if ($GpuLayers) {
    $Args += @("-ngl", $GpuLayers)
}

if ($DraftGpuLayers) {
    $Args += @("-ngld", $DraftGpuLayers)
}

& $ServerExe @Args
