$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LlamaVersion = "b9360"
$LlamaZip = "llama-$LlamaVersion-bin-win-cuda-12.4-x64.zip"
$CudaRuntimeZip = "cudart-llama-bin-win-cuda-12.4-x64.zip"
$LlamaUrl = "https://github.com/ggml-org/llama.cpp/releases/download/$LlamaVersion/$LlamaZip"
$CudaRuntimeUrl = "https://github.com/ggml-org/llama.cpp/releases/download/$LlamaVersion/$CudaRuntimeZip"
$LlamaDir = Join-Path $Root "llama.cpp-$LlamaVersion-cuda12"
$ZipPath = Join-Path $Root $LlamaZip
$CudaRuntimeZipPath = Join-Path $Root $CudaRuntimeZip
$ModelRepo = "unsloth/Qwen3.6-35B-A3B-MTP-GGUF"
$ModelFile = "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
$ModelDir = Join-Path $Root "models\Qwen3.6-35B-A3B-MTP-GGUF"
$ModelPath = Join-Path $ModelDir $ModelFile

New-Item -ItemType Directory -Force -Path $Root | Out-Null
New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null

if (-not (Get-Command hf -ErrorAction SilentlyContinue)) {
    throw "The Hugging Face CLI (hf) is required but was not found in PATH."
}

if (-not (Test-Path (Join-Path $LlamaDir "llama-server.exe"))) {
    Write-Host "Downloading llama.cpp $LlamaVersion..."
    Invoke-WebRequest -Uri $LlamaUrl -OutFile $ZipPath
    Invoke-WebRequest -Uri $CudaRuntimeUrl -OutFile $CudaRuntimeZipPath

    if (Test-Path $LlamaDir) {
        Remove-Item -LiteralPath $LlamaDir -Recurse -Force
    }

    Expand-Archive -LiteralPath $ZipPath -DestinationPath $LlamaDir -Force
    Expand-Archive -LiteralPath $CudaRuntimeZipPath -DestinationPath $LlamaDir -Force
}

if (-not (Test-Path $ModelPath)) {
    Write-Host "Downloading $ModelRepo / $ModelFile ..."
    & hf download $ModelRepo $ModelFile --local-dir $ModelDir
}

Write-Host ""
Write-Host "Setup complete."
Write-Host "llama.cpp: $LlamaDir"
Write-Host "model:     $ModelPath"
