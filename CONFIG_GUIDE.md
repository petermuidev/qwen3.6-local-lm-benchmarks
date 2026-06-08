## Configuration Gap Analysis & Fix Guide

Based on r/LocalLLaMA research, the biggest performance gap is the **runtime**. Switching from upstream llama.cpp to ik_llama.cpp with `--n-cpu-moe` is reported to take Q4_K_M from 16/22 score + 26 tok/s to 22/22 score + **61 tok/s** on identical hardware (RTX 5060 Ti 16GB + DDR4).

> **WARNING — ik_llama.cpp CONFIRMED SLOW ON WINDOWS:** Tested on our hardware (i5-14600KF Raptor Lake + RTX 5060 Ti 16GB + Windows 11): ik_llama.cpp AVX2 build gives **2 tok/s** vs upstream llama.cpp **23.67 tok/s** — 10x slower. AVX512 builds crash with "Illegal instruction" (Raptor Lake's partial AVX512 is incompatible). ik_llama.cpp is **NOT viable on this hardware**. Stick with upstream llama.cpp. See benchmark_results/ for evidence.

---

### Gaps found in current configs

| Gap | Current | Fix | Expected impact |
|-----|---------|-----|-----------------|
| Runtime | llama.cpp b9360 | ik_llama.cpp (built from source) | **+135% tok/s** (26→61 reported on same hardware, **UNVERIFIED on Windows**) |
| MoE offload | `--fit` auto only | `--n-cpu-moe 16` + `-fmoe` (ik_llama.cpp) | Better MoE CPU/GPU split, fused ops |
| MTP (27B dense) | None ("MTP hurts -42%") | `--spec-type mtp:n_max=1,p_min=0.0` (ik_llama.cpp) | +27-150% with ik_llama.cpp MTP (range depends on hardware; 27% on 2x RTX 3090, 150% on Mac M2 Max) |
| MTP (35B MoE) | `--spec-type draft-mtp` (legacy) | `--spec-type mtp:n_max=1,p_min=0.0` (ik_llama.cpp canonical) | Better accept rate with canonical flag |
| Sampling params | None in 27B script | temp=0.6, top-p=0.95, top-k=20, min-p=0, presence-penalty=1.25 | Better output quality |
| KV cache (27B) | q4_0 | q4_0 is fine, but ik_llama.cpp has Q8_KV option | Same or slightly better |
| Batch flags | None on 27B, fixed 2048 on MoE | Remove `-b`/`-ub` when using `--fit` | bobaburger: 74.7 tok/s without batch flags (**UNVERIFIED**) |
| llama.cpp version | b9360 (stale) | b9484+ or ik_llama.cpp | Better MoE offload handling |
| `-rtr` flag | Not used (good) | **Never add `-rtr`** with hybrid CPU/GPU MoE | Prevents GPU offload of CPU tensors |
| `_XL` GGUF | Not used (good) | **Never use Unsloth `_XL` GGUF** with ik_llama.cpp | f16 tensors break ik_llama.cpp |

---

### Path 1: ik_llama.cpp (recommended — proven 61 tok/s on same hardware)

**Source**: https://github.com/ikawrakow/ik_llama.cpp

#### Build on Windows (exact commands)

Prerequisites: Visual Studio Build Tools 2022, clang-cl compiler, CUDA 12.6, CMake, Ninja

```powershell
# 1. Install prerequisites (if not already installed)
# Download VS Build Tools 2022: https://visualstudio.microsoft.com/visual-cpp-build-tools/
# Install with: "Desktop development with C++" workload + clang-cl component
# Download CUDA 12.6: https://developer.nvidia.com/cuda-downloads
# Install CMake: https://cmake.org/download/ (or via winget)
# Install Ninja: https://ninja-build.org/ (or via winget)

winget install Kitware.CMake
winget install Ninja-build.Ninja

# 2. Clone ik_llama.cpp
git clone https://github.com/ikawrakow/ik_llama.cpp.git
cd ik_llama.cpp

# 3. Build with CUDA support (RTX 5060 Ti = Blackwell arch 120)
cmake -B build -G Ninja ^
  -DCMAKE_C_COMPILER=clang-cl ^
  -DCMAKE_CXX_COMPILER=clang-cl ^
  -DCMAKE_CUDA_ARCHITECTURES="120-real" ^
  -DGGML_CUDA=ON ^
  -DGGML_NATIVE=ON ^
  -DGGML_BLAS=OFF

cmake --build build --config Release

# Output: build/bin/Release/llama-server.exe
# Copy to your benchmarks dir as ik_llama-server.exe or into a dedicated folder
```

**Note**: If `120-real` doesn't work for Blackwell, try `120` or `89-real` (Ampere fallback). Check your GPU compute capability with `nvidia-smi --query-gpu=compute_cap --format=csv`.

#### Pre-built Windows binaries (skip building from source)

If you don't want to build from source, pre-built Windows binaries exist:

| Source | Link | Notes |
|--------|------|-------|
| Thireus releases | https://github.com/Thireus/ik_llama.cpp/releases | macOS, Ubuntu, Windows |
| X5R HuggingFace | https://huggingface.co/X5R/ik_llama.cpp | Pre-built Windows binary |
| Danmoreng build script | See [Reddit thread](https://reddit.com/r/LocalLLaMA/comments/1mga3ox/) | PowerShell all-in-one |

**Caveat**: Pre-built binaries may not include the latest MTP fixes. Check release dates against PR #1698 merge date.

#### IQ4_KS — The 16GB VRAM Sweet Spot (27B dense)

From [Pablo_the_brave, 81pts on Reddit](https://reddit.com/r/LocalLLaMA/comments/1tkmgwj/):
- **IQ4_KS** (14.1GB) fits entirely in 16GB VRAM with room for 105K context
- Requires ik_llama.cpp (KS/KSS quants not in upstream llama.cpp)
- **1.5-1.75x faster** than IQ4_XS with comparable quality (PPL 7.4040)
- With q4_0 Hadamard KV cache (`-khad -vhad -ctk q4_0 -ctv q4_0`)
- Eliminates "blank outputs" issue seen with some quants
- Model: `cHunter789/Qwen3.6-27B-i1-IQ4_KS-GGUF`

```powershell
# Download IQ4_KS model
hf download cHunter789/Qwen3.6-27B-i1-IQ4_KS-GGUF Qwen3.6-27B.i1-IQ4_KS.gguf --local-dir models\Qwen3.6-27B-IQ4_KS
```

#### ik_llama.cpp key flags

| Flag | Purpose | Notes |
|------|---------|-------|
| `--fit` | Auto-fit tensors to VRAM | Cannot combine with `--override-tensor`, `--cpu-moe`, `--n-cpu-moe` |
| `--n-cpu-moe N` | Keep MoE of first N layers in CPU | Use WITHOUT `--fit`. bobaburger: `--n-cpu-moe 16` gave 61 tok/s |
| `--cpu-moe` | Keep ALL MoE weights in CPU | Use WITHOUT `--fit`. Slower than selective `--n-cpu-moe` |
| `-fmoe` / `--fused-moe` | Fused MoE FFN up/gate | Speedup for MoE models |
| `-ooae` / `--offload-only-active-experts` | Only offload active experts to GPU | ON by default in ik_llama.cpp |
| `-fa on` | Flash Attention | ON by default in ik_llama.cpp |
| `--spec-type mtp:n_max=1,p_min=0.0` | MTP speculative decoding | Canonical flag (replaces legacy `--spec-type draft-mtp`) |
| `-ctk` / `-ctv` | KV cache types | ik_llama.cpp adds `Q8_KV` and Hadamard transforms `-khad`/`-vhad` |
| `-nkvo` / `--no-kv-offload` | Keep KV on CPU | Frees VRAM but hurts PP speed |
| `-ser 1,N` | Smart Expert Reduction | Force N active experts (experimental) |
| `-ot "pattern=CPU"` | Override tensor storage | Example: `-ot "blk.[1-9][0-9].ffn=CPU"` |
| `--defer-experts` | Defer expert mmap residency | Faster load time |

**CRITICAL**: Do NOT use `-rtr` with `--n-cpu-moe` or `--cpu-moe`. `-rtr` forces row-interleaved repack which prevents GPU offload of CPU-stored tensors, drastically hurting PP speed.

**CRITICAL**: Do NOT use Unsloth `_XL` GGUF models with ik_llama.cpp — they contain f16 tensors which don't work.

#### Proven config for 35B MoE on RTX 5060 Ti 16GB + DDR4 (bobaburger — **UNVERIFIED**)

> **Note**: The 61 tok/s and 74.7 tok/s bobaburger numbers are **unverified**. No Reddit post from "bobaburger" found in our evidence collection. These numbers likely reflect DDR5 + Linux, not our DDR4 + Windows setup. Two Reddit users report disappointing ik_llama.cpp performance on Windows. **Benchmark on our hardware before relying on these claims.**

```powershell
# ik_llama.cpp server with n-cpu-moe (61 tok/s reported, UNVERIFIED on Windows)
ik_llama-server.exe ^
  -m Qwen3.6-35B-A3B-UD-Q4_K_M.gguf ^
  --host 127.0.0.1 --port 8080 ^
  -t 16 -c 65536 -n 32768 -np 1 ^
  -fa on ^
  --n-cpu-moe 16 ^
  -fmoe ^
  -ctk q8_0 -ctv q8_0 ^
  --no-mmap --no-warmup ^
  --cache-ram 0 ^
  --jinja
```

Key differences from current config:
- Uses ik_llama.cpp (not upstream llama.cpp b9360)
- Uses `--n-cpu-moe 16` WITHOUT `--fit` (ik_llama.cpp handles this correctly, no crash)
- Uses `-fmoe` for fused MoE ops
- No `-b`/`-ub` batch flags (bobaburger found removing them gives 74.7 tok/s with `--fit` alone)

#### Proven config for 27B dense with MTP (ik_llama.cpp PR #1698, merged)

ik_llama.cpp now supports MTP for Qwen 3.6 **dense models** (27B). 35B MoE does NOT yet have MTP.

Requires GGUF with MTP layer preserved. Use:
- Radamanthys11/Qwen3.6-27B-MTP-Q8_0-GGUF (pre-built, Q8_0 MTP)
- Or create your own using the `qwen-35-mtp-gguf` branch

```powershell
# ik_llama.cpp 27B dense with MTP (expected +27-30% over baseline)
ik_llama-server.exe ^
  -m Qwen3.6-27B-MTP-Q8_0.gguf ^
  --host 127.0.0.1 --port 8080 ^
  -t 16 -c 65536 -n 32768 -np 1 ^
  -fa on ^
  --spec-type mtp:n_max=1,p_min=0.0 ^
  -ctk q4_0 -ctv q4_0 ^
  --no-mmap --no-warmup ^
  --cache-ram 0 ^
  --jinja
```

**IMPORTANT**: Use `--spec-type mtp:n_max=1,p_min=0.0` (draft-max=1, not 2). draft-max=2 gives diminishing returns (51% accept, sometimes slower). draft-max=1 gives 82-87% accept rate.

Benchmark evidence (2x RTX 3090, ik_llama.cpp):
- 27B layer mode: 23.3 → 29.6 tok/s (+27%)
- 27B graph mode: 36.8 → 41.6 tok/s (+13%)

---

### Path 2: atomic-llama-cpp-turboquant (alternative — +28-36% on MoE)

**Source**: https://github.com/AtomicBot-ai/atomic-llama-cpp-turboquant

This is a **different fork** from ik_llama.cpp. It adds TurboQuant KV cache and NextN speculative decoding.

#### Key features

| Feature | Details |
|---------|---------|
| TurboQuant KV | `turbo3` (3-bit, ~4.3x compression, recommended) or `turbo2`/`turbo4` |
| Weight quants | `TQ3_1S` (3-bit), `TQ4_1S` (4-bit) |
| NextN spec | `--spec-type nextn` with `-md` pointing to same `_MTP.gguf` |
| Pre-built GGUFs | AtomicChat/Qwen3.6-35B-A3B-UDT-MTP-GGUF (5 quants) |

#### Proven config for 35B MoE

```powershell
# TurboQuant with NextN speculative decoding (+28-36% on 35B MoE)
atomic-llama-server.exe ^
  -m AtomicChat/Qwen3.6-35B-A3B-UDT-MTP-TQ4_1S.gguf ^
  -md AtomicChat/Qwen3.6-35B-A3B-UDT-MTP-TQ4_1S.gguf ^
  --spec-type nextn ^
  --host 127.0.0.1 --port 8080 ^
  -t 16 -c 65536 -n 32768 -np 1 ^
  -fa on ^
  -ctk turbo3 -ctv turbo3 ^
  --no-mmap ^
  --cache-ram 0 ^
  --jinja
```

**Note**: This uses upstream llama.cpp as base (not ik_llama.cpp). You can't mix the two. Choose one path at a time for benchmarking.

#### Download pre-built TurboQuant GGUFs

```powershell
# Using huggingface-cli (hf)
hf download AtomicChat/Qwen3.6-35B-A3B-UDT-MTP-GGUF Qwen3.6-35B-A3B-UDT-MTP-TQ4_1S.gguf --local-dir models\TurboQuant
hf download AtomicChat/Qwen3.6-27B-UDT-MTP-GGUF Qwen3.6-27B-UDT-MTP-Q4_K_XL.gguf --local-dir models\TurboQuant
```

---

### Path 3: ngram-mod + MTP combo (ik_llama.cpp, experimental)

Combine ngram speculative decoding with MTP for potentially higher acceptance:

```powershell
# ngram-mod + MTP combo (ik_llama.cpp)
ik_llama-server.exe ^
  -m Qwen3.6-35B-A3B-UD-Q4_K_M.gguf ^
  --host 127.0.0.1 --port 8080 ^
  -t 16 -c 65536 -n 32768 -np 1 ^
  -fa on ^
  --n-cpu-moe 16 ^
  -fmoe ^
  --spec-type ngram-mod:n_max=64,n_min=2,ngram_size_n=8 ^
  --spec-type mtp:n_max=1,p_min=0.0 ^
  -ctk q8_0 -ctv q8_0 ^
  --no-mmap --no-warmup ^
  --cache-ram 0 ^
  --jinja
```

**Note**: This requires MTP GGUF. The 35B MoE MTP is NOT yet supported in ik_llama.cpp (only 27B dense has MTP). This combo is for 27B dense only.

---

### Fix suggestions for current upstream llama.cpp configs

These fixes apply immediately without switching runtime:

#### 27B dense (start-server-27b-iq3xxs.ps1)

| Current | Fix | Why |
|---------|-----|-----|
| No sampling params | Add: temp=0.6, top-p=0.95, top-k=20, min-p=0, presence-penalty=1.25 | Reddit consensus for Qwen 3.6 quality |
| `--no-warmup` | Keep | Saves startup time |
| `--cache-ram 0` | Keep | Prevents DDR4 speed collapse |
| q4_0 KV | Keep | Lossless on Qwen hybrid, frees VRAM for dense |

No major speed fix possible without switching to ik_llama.cpp. The 27B config is already well-optimized for upstream llama.cpp.

#### 35B MoE (start-server-q4ks-vanilla.ps1)

| Current | Fix | Why |
|---------|-----|-----|
| llama.cpp b9360 | Upgrade to b9484+ or switch to ik_llama.cpp | Better MoE offload handling |
| No `--n-cpu-moe` | Can't add on upstream (crashes with `--fit`) | ik_llama.cpp handles this correctly |
| q8_0 KV | Keep | Best for 35B MoE hybrid |
| `--cache-ram 0` | Keep | Prevents DDR4 speed collapse |

**The biggest single fix**: switch to ik_llama.cpp with `--n-cpu-moe 16`. This alone reportedly takes 26→61 tok/s on same hardware (**UNVERIFIED on Windows**).

---

### Recommended benchmark order

1. ~~ik_llama.cpp Windows validation~~ **FAILED** — 2 tok/s vs 23.67 tok/s on upstream llama.cpp
2. **Upstream llama.cpp optimizations**: Focus on what works — MTP with upstream llama.cpp, quant tuning
3. **Upstream llama.cpp 27B + MTP**: Test with `--spec-type draft-mtp` and MTP GGUF (Radamanthys11)
4. **Upstream llama.cpp 35B MoE**: Retest baseline, try newer llama.cpp builds (b9484+)
5. **TurboQuant 35B MoE** (if interested): Different fork, may not have same Windows penalty

---

### Reference: results on RTX 5060 Ti 16GB hardware

| Config | Runtime | Score | Speed | Source | OS |
|--------|---------|-------|-------|--------|----|
| IQ3_XXS 27B (our baseline) | llama.cpp b9360 | 4/4 | **23.67 tok/s** | Our benchmark | Windows |
| IQ3_XXS 27B (ik_llama AVX2) | ik_llama.cpp b4829 | — | **2 tok/s** | Our benchmark | Windows |
| Q4_K_M + n-cpu-moe 16 | ik_llama.cpp | 22/22 | **61 tok/s** | bobaburger (**UNVERIFIED**) | Unknown (likely Linux) |
| Q4_K_M + fit (no batch flags) | ik_llama.cpp | — | **74.7 tok/s** | bobaburger (**UNVERIFIED**) | Unknown (likely Linux) |
| IQ3_S (fits entirely in VRAM) | llama.cpp | — | 98 tok/s | njannasch.dev | Linux |
| IQ3_S + MTP (fits VRAM) | llama.cpp | — | 144 tok/s | njannasch.dev | Linux |

**Key insight**: ik_llama.cpp is 10x slower than llama.cpp on our Windows hardware (AVX2) and crashes with AVX512. All top ik_llama benchmarks are Linux. **Upstream llama.cpp is the right runtime for our setup.**

---

### Model download commands

```powershell
# Current models (already have these)
hf download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-UD-IQ3_XXS.gguf --local-dir models\Qwen3.6-27B-GGUF
hf download unsloth/Qwen3.6-35B-A3B-MTP-GGUF Qwen3.6-35B-A3B-UD-Q4_K_S.gguf --local-dir models\Qwen3.6-35B-A3B-MTP-GGUF

# New models needed for ik_llama.cpp MTP
hf download Radamanthys11/Qwen3.6-27B-MTP-Q8_0-GGUF Qwen3.6-27B-MTP-Q8_0.gguf --local-dir models\Qwen3.6-27B-MTP-GGUF

# IQ4_KS for 27B — 16GB VRAM sweet spot (ik_llama.cpp only)
hf download cHunter789/Qwen3.6-27B-i1-IQ4_KS-GGUF Qwen3.6-27B.i1-IQ4_KS.gguf --local-dir models\Qwen3.6-27B-IQ4_KS

# New models needed for TurboQuant
hf download AtomicChat/Qwen3.6-35B-A3B-UDT-MTP-GGUF Qwen3.6-35B-A3B-UDT-MTP-TQ4_1S.gguf --local-dir models\TurboQuant
hf download AtomicChat/Qwen3.6-27B-UDT-MTP-GGUF Qwen3.6-27B-UDT-MTP-Q4_K_XL.gguf --local-dir models\TurboQuant
```