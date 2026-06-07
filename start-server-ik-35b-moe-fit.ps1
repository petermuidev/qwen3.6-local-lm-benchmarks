$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "ik-llama.cpp-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-35B-A3B-MTP-GGUF\Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing ik_llama.cpp server at $ServerExe. Build ik_llama.cpp first — see CONFIG_GUIDE.md"
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download from Unsloth first."
}

# ik_llama.cpp 35B MoE --fit auto config (no manual overrides)
# Source: bobaburger (r/LocalLLaMA) — 74.7 tok/s on same hardware with --fit alone
#
# KEY: --fit auto determines GPU/CPU/MoE split automatically
#   Cannot combine with --override-tensor, --cpu-moe, --n-cpu-moe
# -fmoe: fused MoE FFN up/gate ops (speedup)
# No -b/-ub: bobaburger found removing batch flags gives 74.7 vs ~61 tok/s
#   Removing batch flags lets --fit allocate VRAM optimally
#
# CRITICAL: do NOT add -rtr (breaks hybrid CPU/GPU MoE offload)
# CRITICAL: do NOT use Unsloth _XL GGUF (f16 tensors break ik_llama.cpp)

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$FitMargin    = if ($env:LLAMA_FIT_MARGIN)   { $env:LLAMA_FIT_MARGIN }   else { "1024" }
$CacheTypeK   = if ($env:LLAMA_CACHE_TYPE_K) { $env:LLAMA_CACHE_TYPE_K } else { "q8_0" }
$CacheTypeV   = if ($env:LLAMA_CACHE_TYPE_V) { $env:LLAMA_CACHE_TYPE_V } else { "q8_0" }

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "32768",
    "-np", "1",
    "--fit",
    "--fit-margin", $FitMargin,
    "-fmoe",
    "-fa", "on",
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "--no-mmap",
    "--no-warmup",
    "--cache-ram", "0"
)

Write-Host "Starting ik_llama.cpp server (35B MoE --fit auto PROVEN config)..."
Write-Host "  Runtime:  ik_llama.cpp (required for --fit without crash)"
Write-Host "  Model:    Qwen3.6-35B-A3B-UD-Q4_K_M (21.1GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit auto, margin=$FitMargin MiB)"
Write-Host "  Spec:     NONE (35B MoE MTP not yet in ik_llama.cpp)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV"
Write-Host "  Cache:    prompt cache DISABLED (--cache-ram 0)"
Write-Host "  Extras:   --fit, -fmoe, no batch flags, no-mmap, no-warmup"
Write-Host "  Expected: ~74 tok/s (bobaburger, same hardware, --fit without batch)"
Write-Host ""

& $ServerExe @Args