$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-27B-GGUF\Qwen3.6-27B-UD-IQ3_XXS.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}
if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download with: hf download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-UD-IQ3_XXS.gguf --local-dir models\Qwen3.6-27B-GGUF"
}

# Long-context config for 27B Dense on RTX 5060 Ti 16GB
# Benchmarked: 28.8 t/s short, 25.8 t/s at 15K context
#
# Why no MTP:
#   MTP draft cache eats ~300MB VRAM. At 4K+ context speed collapses
#   to 10 t/s. Without MTP, 26 t/s STABLE at 15K context.
#
# Why IQ3_XXS not IQ3_M:
#   IQ3_XXS is 11.2GB - more VRAM headroom for KV cache.
#   Non-MTP GGUF - no wasted MTP head weights.
#
# Why 16K context not 64K:
#   KEY FINDING: context size controls VRAM allocation. At 64K,
#   --fit reserves KV for full 64K and offloads model layers to
#   CPU = 13 t/s. At 16K, more layers fit in VRAM = 26 t/s.
#   16K context is enough for most multi-turn conversations.
#
# Why -ngl 99 -fit off:
#   With 16K context, IQ3_XXS fits entirely in VRAM. -ngl 99
#   puts all layers on GPU. -fit off prevents over-conservative
#   KV reservation. At 16K q4_0 KV the total is ~12.4GB.
#
# Why q4_0 KV not q8_0:
#   At 16K context, q4_0 KV keeps total VRAM ~12.4GB = all GPU.
#   q8_0 KV would be ~13.5GB = some layers spill to CPU = slower.

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "16384" }
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
    "-ngl", "99",
    "-fit", "off",
    "-fa", "on",
    "--kv-unified",
    "--no-mmproj",
    "-ctk", "q4_0",
    "-ctv", "q4_0",
    "-rea", "off"
)

Write-Host "Starting llama-server - 27B IQ3_XXS long context optimized"
Write-Host "  Model:    Qwen3.6-27B-IQ3_XXS 11.2GB fits 16GB VRAM with 16K ctx"
Write-Host "  GPU:      -ngl 99 -fit off - all layers on GPU at 16K context"
Write-Host "  Spec:     NONE - no MTP draft cache saves VRAM for KV"
Write-Host "  Context:  $Context (16K sweet spot for VRAM fit)"
Write-Host "  KV cache: K=q4_0 V=q4_0 keeps total ~12.4GB all in VRAM"
Write-Host "  Reason:   off - prevents empty content issue with clients like opencode"
Write-Host "  Speed:    28.8 t/s short, 25.8 t/s at 15K context"
Write-Host ""

& $ServerExe @Args
