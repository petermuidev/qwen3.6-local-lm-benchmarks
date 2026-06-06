$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaDir = Join-Path $Root "llama.cpp-b9360-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.6-35B-A3B-MTP-GGUF\Qwen3.6-35B-A3B-UD-Q4_K_S.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}

if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath"
}

# Vanilla baseline - UD-Q4_K_S without MTP
# Compare against Q4_K_M vanilla (36.1 tok/s) to measure quant size impact

$Context      = if ($env:LLAMA_CONTEXT)      { $env:LLAMA_CONTEXT }      else { "65536" }
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
    "-ctk", $CacheTypeK,
    "-ctv", $CacheTypeV,
    "--no-mmap",
    "--cache-ram", "0"
)

Write-Host "Starting llama-server (UD-Q4_K_S vanilla baseline - NO MTP)..."
Write-Host "  Model:    Qwen3.6-35B-A3B-UD-Q4_K_S (Unsloth, 19.9GB)"
Write-Host "  GPU:      RTX 5060 Ti 16GB (--fit auto)"
Write-Host "  Spec:     NONE (baseline)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: K=$CacheTypeK V=$CacheTypeV"
Write-Host "  Cache:    prompt cache DISABLED (--cache-ram 0)"
Write-Host ""

& $ServerExe @Args