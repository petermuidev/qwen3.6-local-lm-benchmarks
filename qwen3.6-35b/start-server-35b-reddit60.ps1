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

# Reddit 60 tok/s config — matched as closely as possible
# Key differences from our old vanilla config:
#   1. Added --fit on (was MISSING — auto GPU/CPU split is critical)
#   2. Added --kv-unified (saves VRAM with unified KV cache)
#   3. Added --no-mmproj (skip multimodal projector, saves VRAM)
#   4. REMOVED --no-mmap (allow mmap for better MoE expert paging)
#   5. REMOVED --cache-ram 0 (allow prompt caching)
#   6. Context 64000 (matches Reddit config, slightly less KV pressure)

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "64000" }
$Port         = if ($env:LLAMA_PORT)         { $env:LLAMA_PORT }         else { "8080" }
$HostAddr     = if ($env:LLAMA_HOST)         { $env:LLAMA_HOST }         else { "127.0.0.1" }
$Threads      = if ($env:LLAMA_THREADS)      { $env:LLAMA_THREADS }      else { "16" }
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
    "-fa", "on",
    "--fit", "on",
    "--kv-unified",
    "--no-mmproj",
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV
)

Write-Host "Starting llama-server (Reddit 60 tok/s matched config)..."
Write-Host "  Model:    Qwen3.6-35B-A3B-UD-Q4_K_S (19.9GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit on, --kv-unified)"
Write-Host "  Spec:     NONE (baseline, add MTP later)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV, unified"
Write-Host "  CHANGES:  +fit on, +kv-unified, +no-mmproj, -no-mmap, -cache-ram-0"
Write-Host ""

& $ServerExe @Args
