$ErrorActionPreference = "Stop"

# Build helper for ik_llama.cpp on Windows
# ik_llama.cpp has NO pre-built release binaries — must build from source
# Source: https://github.com/ikawrakow/ik_llama.cpp
# Build docs: https://github.com/ikawrakow/ik_llama.cpp/blob/main/docs/build.md

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$IkLlamaDir = Join-Path $Root "ik-llama.cpp-cuda12"
$CloneDir = Join-Path $Root "ik_llama.cpp-src"

Write-Host "=== ik_llama.cpp Build Helper ==="
Write-Host ""

# Step 1: Check prerequisites
Write-Host "Step 1: Checking prerequisites..."

$prereqs = @(
    @{ Name = "Visual Studio Build Tools 2022"; Check = "vswhere"; Hint = "Download: https://visualstudio.microsoft.com/visual-cpp-build-tools/ Install 'Desktop development with C++' + clang-cl" },
    @{ Name = "clang-cl"; Check = "clang-cl"; Hint = "Install via VS Build Tools clang-cl component" },
    @{ Name = "CMake"; Check = "cmake"; Hint = "winget install Kitware.CMake" },
    @{ Name = "Ninja"; Check = "ninja"; Hint = "winget install Ninja-build.Ninja" },
    @{ Name = "CUDA Toolkit"; Check = "nvcc"; Hint = "Download CUDA 12.6+: https://developer.nvidia.com/cuda-downloads" }
)

$missing = @()
foreach ($pr in $prereqs) {
    $found = Get-Command $pr.Check -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "  OK: $($pr.Name) at $($found.Source)"
    } else {
        Write-Host "  MISSING: $($pr.Name) — $($pr.Hint)"
        $missing += $pr.Name
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "Install missing prerequisites before continuing."
    Write-Host "After installing, restart PowerShell and run this script again."
    throw "Missing prerequisites: $($missing -join ', ')"
}

# Step 2: Check GPU compute capability
Write-Host ""
Write-Host "Step 2: Checking GPU compute capability..."
$gpuCap = & nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>$null
if ($gpuCap) {
    Write-Host "  GPU compute capability: $gpuCap"
    Write-Host "  RTX 5060 Ti (Blackwell) = compute 12.0 → use CMAKE_CUDA_ARCHITECTURES=120-real"
    Write-Host "  If 120-real fails, try 120 or 89-real (Ampere fallback)"
} else {
    Write-Host "  Could not detect GPU compute capability. Defaulting to 120-real for Blackwell."
}

# Step 3: Clone ik_llama.cpp
Write-Host ""
Write-Host "Step 3: Cloning ik_llama.cpp..."
if (Test-Path $CloneDir) {
    Write-Host "  Source already exists at $CloneDir. Skipping clone."
    Write-Host "  To update: cd $CloneDir; git pull"
} else {
    git clone https://github.com/ikawrakow/ik_llama.cpp.git $CloneDir
    if (-not (Test-Path $CloneDir)) {
        throw "Clone failed. Check git and internet connection."
    }
    Write-Host "  Cloned to $CloneDir"
}

# Step 4: Build with CMake
Write-Host ""
Write-Host "Step 4: Building ik_llama.cpp with CUDA..."
Write-Host "  Running CMake configure + build..."

$CudaArch = if ($env:IK_CUDA_ARCH) { $env:IK_CUDA_ARCH } else { "120-real" }

Push-Location $CloneDir

cmake -B build -G Ninja `
    -DCMAKE_C_COMPILER=clang-cl `
    -DCMAKE_CXX_COMPILER=clang-cl `
    -DCMAKE_CUDA_ARCHITECTURES=$CudaArch `
    -DGGML_CUDA=ON `
    -DGGML_NATIVE=ON `
    -DGGML_BLAS=OFF `
    -DCMAKE_BUILD_TYPE=Release

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "CMake configure failed. If CUDA_ARCH=$CudaArch failed, try IK_CUDA_ARCH=89-real"
}

cmake --build build --config Release

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "Build failed. Check CUDA toolkit version and compiler setup."
}

Pop-Location

# Step 5: Copy output to expected directory
$BuiltExe = Join-Path $CloneDir "build\bin\Release\llama-server.exe"
if (-not (Test-Path $BuiltExe)) {
    # Try other common output paths
    $BuiltExe = Join-Path $CloneDir "build\llama-server.exe"
}

if (-not (Test-Path $BuiltExe)) {
    throw "Built llama-server.exe not found. Check build output in $CloneDir\build\"
}

New-Item -ItemType Directory -Force -Path $IkLlamaDir | Out-Null
Copy-Item -LiteralPath $BuiltExe -Destination (Join-Path $IkLlamaDir "llama-server.exe") -Force

# Also copy shared libs if they exist in the same build dir
$BuildDir = Split-Path -Parent $BuiltExe
$DllFiles = Get-ChildItem -LiteralPath $BuildDir -Filter "*.dll" -ErrorAction SilentlyContinue
foreach ($dll in $DllFiles) {
    Copy-Item -LiteralPath $dll.FullName -Destination $IkLlamaDir -Force
}

Write-Host ""
Write-Host "=== Build complete ==="
Write-Host "  ik_llama.cpp server: $IkLlamaDir\llama-server.exe"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "  1. Test: .\start-server-ik-35b-moe-ncpumoe16.ps1"
Write-Host "  2. Benchmark: python benchmark_qwen_mtp.py"
Write-Host "  3. Compare: expected ~61 tok/s vs current ~33 tok/s"
Write-Host ""
Write-Host "  See CONFIG_GUIDE.md for full optimization details."