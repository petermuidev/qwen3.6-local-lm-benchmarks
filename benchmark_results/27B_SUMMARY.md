# 27B Dense Benchmark Summary

## Hardware: i5-14600KF + RTX 5060 Ti 16GB + DDR4 + Windows 11

## Results

| Config | Runtime | Speed | Passed | Why |
|--------|---------|-------|--------|-----|
| IQ3_XXS (11.17GB) | llama.cpp b9360 | **23.67 tok/s** | 4/4 | Fits in VRAM |
| IQ3_XXS | ik_llama.cpp AVX2 | 2.04 tok/s | - | 10x slower on Windows |
| IQ3_XXS | ik_llama.cpp AVX512 | CRASH | - | Illegal instruction (Raptor Lake) |
| Q8_0 MTP (15.3GB) | llama.cpp b9360 | 3.15 tok/s | 3/4 | DDR4 offload kills speed |

## Key Lessons

1. **VRAM fit is everything**. IQ3_XXS (11.17GB) fits in 16GB with KV room = 23.67 tok/s. Anything larger forces DDR4 offload = 2-3 tok/s (7-10x penalty).

2. **ik_llama.cpp is dead on Windows Raptor Lake**. AVX512 builds crash (partial AVX512 incompatibility). AVX2 build runs but is 10x slower than upstream llama.cpp. All ik_llama.cpp speed benchmarks are Linux + AVX512 + DDR5.

3. **MTP hurts on 16GB VRAM**. The MTP GGUF is Q8_0 at 15.3GB — too big. DDR4 offload negates any MTP speedup. MTP only helps when model fits in VRAM with headroom.

4. **Upstream llama.cpp is the right runtime** for this hardware. No alternative runtime beats it on Windows.

## 27B Winner

**IQ3_XXS on llama.cpp b9360**: 23.67 tok/s, 4/4 tasks passed.

## What could improve 27B further

- Smaller MTP GGUF (~11GB) if one gets created — would allow MTP without DDR4 offload
- Newer llama.cpp build (b9484+) — possible incremental gains
- Linux dual-boot — would unlock ik_llama.cpp + AVX512 + MTP (potential 60+ tok/s)
