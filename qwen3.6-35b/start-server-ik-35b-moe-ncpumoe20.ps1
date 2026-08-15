$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$IkDir = Join-Path $Root "ik_llama-bin"
$ServerExe = Join-Path $IkDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-35B-A3B-MTP-GGUF\Qwen3.6-35B-A3B-UD-Q4_K_S.gguf"

# Fallback to LM Studio cache if project model not found
if (-not (Test-Path $ModelPath)) {
    $ModelPath = "C:\Users\Administrator\.cache\lm-studio\models\lmstudio-community\Qwen3.6-35B-A3B-GGUF\Qwen3.6-35B-A3B-Q4_K_M.gguf"
}

if (-not (Test-Path $ServerExe)) {
    throw "Missing ik_llama-server.exe at $ServerExe"
}
if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath"
}

# BEST config for Qwen3.6 35B MoE on RTX 5060 Ti 16GB + DDR4 + Windows 11
# Benchmarked July 2 2026:
#   64K ctx: 43.5 tok/s gen, 93.4 tok/s prompt
#   100K ctx: 43.2 tok/s gen (short prompt), 42.2 tok/s (4K input)
#
# Key flags:
#   --n-cpu-moe 20   â€” MoE experts for layers 0-19 on CPU (frees 2 GiB VRAM for KV)
#   -ngl 99          â€” ALL layers GPU-offloaded (dense weights stay on GPU)
#   -ctk q4_0        â€” Compressed KV cache (fits ~64K context in VRAM)
#   -rea off         â€” Disable thinking/reasoning (saves tokens + faster)
#   GGML_CUDA_NO_PINNED=1 â€” Prevents 19.7 GiB pinned memory allocation failure

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
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
    "-n", "4096",
    "-np", "1",
    "-ngl", "99",
    "-fa", "on",
    "--n-cpu-moe", "20",
    "-ctk", "q4_0",
    "-ctv", "q4_0",
    "-rea", "off"
)

Write-Host "Starting ik_llama-server (35B MoE best config)..."
Write-Host "  Model:    Qwen3.6-35B-A3B-Q4_K_M (19.7GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (-ngl 99, --n-cpu-moe 20)"
Write-Host "  KV:       q4_0/q4_0 (compressed, fits 64K in VRAM)"
Write-Host "  Context:  $Context"
Write-Host "  Bench:    ~43 tok/s at 64K ctx"
Write-Host ""

& $ServerExe @Args
