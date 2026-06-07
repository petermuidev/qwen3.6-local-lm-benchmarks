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

# ik_llama.cpp 35B MoE config -- PROVEN 61 tok/s on RTX 5060 Ti 16GB + DDR4
# Source: bobaburger (r/LocalLLaMA) — same hardware, 26→61 tok/s
#
# KEY: --n-cpu-moe 16 keeps MoE weights of first 16 layers in CPU
#   In ik_llama.cpp this works correctly (no crash like upstream llama.cpp)
#   Cannot combine with --fit (use one or the other)
# -fmoe: fused MoE FFN up/gate ops (speedup)
# No -b/-ub: removing batch flags lets --n-cpu-moe optimize better
#
# CRITICAL: do NOT add -rtr (breaks hybrid CPU/GPU MoE offload)
# CRITICAL: do NOT use Unsloth _XL GGUF (f16 tensors break ik_llama.cpp)

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
$NCpuMoe      = if ($env:LLAMA_N_CPU_MOE)    { $env:LLAMA_N_CPU_MOE }    else { "16" }
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
    "-ngl", "99",
    "--n-cpu-moe", $NCpuMoe,
    "-fmoe",
    "-fa", "on",
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "--no-mmap",
    "--no-warmup",
    "--cache-ram", "0"
)

Write-Host "Starting ik_llama.cpp server (35B MoE --n-cpu-moe PROVEN config)..."
Write-Host "  Runtime:  ik_llama.cpp (required for --n-cpu-moe without crash)"
Write-Host "  Model:    Qwen3.6-35B-A3B-UD-Q4_K_M (21.1GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (attn+shared on GPU, MoE first $NCpuMoe layers on CPU)"
Write-Host "  Spec:     NONE (35B MoE MTP not yet in ik_llama.cpp)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV"
Write-Host "  Cache:    prompt cache DISABLED (--cache-ram 0)"
Write-Host "  Extras:   -fmoe, -ngl 99, --n-cpu-moe $NCpuMoe, no-mmap, no-warmup"
Write-Host "  Expected: ~61 tok/s (bobaburger, same hardware)"
Write-Host ""

& $ServerExe @Args