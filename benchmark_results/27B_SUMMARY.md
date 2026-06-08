# 27B Dense Benchmark Summary

## Hardware: i5-14600KF + RTX 5060 Ti 16GB + DDR4 + Windows 11

## Results

| Config | Runtime | Speed | Passed | Notes |
|--------|---------|-------|--------|-------|
| IQ3_XXS (11.2GB, no MTP) | llama.cpp b9360 | 19.86 tok/s | 4/4 | Old baseline, no MTP GGUF |
| **IQ3_M + MTP draft-max=3 (12GB)** | llama.cpp b9360 | **35.49 tok/s** | 4/4 | **1.79x speedup — 27B winner** |
| IQ3_M + MTP + ngram-mod | llama.cpp b9360 | 29.12 tok/s | - | ngram overhead hurts, worse than MTP alone |
| IQ3_M + MTP + q4_0 draft KV | llama.cpp b9360 | 30.85 tok/s | - | Lower draft KV quant hurts acceptance rate |
| IQ4_XS + MTP (15GB) | llama.cpp b9360 | 0.70 tok/s | - | Overflows 16GB VRAM with f16 draft cache |
| IQ3_XXS (ik_llama.cpp AVX2) | ik_llama.cpp b4829 | 2.04 tok/s | - | 10x slower on Windows |
| Q8_0 MTP (28GB) | llama.cpp b9360 | 3.15 tok/s | 3/4 | DDR4 offload, too big |

## Key Lessons

1. **MTP works for 27B because it fits in VRAM**. Unlike 35B MoE where DDR4 is the bottleneck, 27B dense (12GB) fits entirely in 16GB VRAM. MTP only adds GPU compute, giving 1.79x speedup.

2. **IQ4_XS + MTP overflows VRAM**. The 15GB model + f16 draft KV cache (default) + 64k context > 16GB. Result: 0.70 tok/s — worse than no MTP. Must use IQ3_M (12GB) to leave room for draft cache.

3. **draft-max=3 is optimal** (per froggeric 1233pts). Acceptance rate is ~67% on upstream llama.cpp (lower than ik_llama.cpp's 82-87% but still worth it).

4. **ngram-mod doesn't help on 27B MTP**. The overhead of ngram search outweighs the marginal acceptance improvement when MTP already drafts well.

5. **q4_0 draft KV hurts acceptance**. Lower quant on the draft cache reduces prediction quality, lowering acceptance rate from 67% to lower. f16 draft cache is the default for a reason.

6. **q4_0 KV cache is fine for 27B dense generation**. Unlike 35B MoE where q4_0 hurts, the dense model has no CPU offload bottleneck — q4_0 KV works well.

7. **ik_llama.cpp is still dead on Windows**. Same 10x penalty as 35B tests. All ik_llama.cpp MTP benchmarks (82-87% acceptance, IQ4_KS) are Linux-only.

## 27B Winner

**IQ3_M + MTP draft-max=3 on llama.cpp b9360**: 35.49 tok/s, 4/4 tasks passed.

## What could improve 27B further

- **ik_llama.cpp on Linux**: Would unlock IQ4_KS (14.1GB), higher MTP acceptance (82-87%), and potentially 50-70+ tok/s
- **Newer llama.cpp build**: b9484+ may have better MTP implementation
- **IQ3_XXS-MTP GGUF**: Doesn't exist yet — would be ~10GB, more VRAM headroom
- **draft-max=1 vs 3**: Could test if single-draft has better acceptance tradeoff

## Long Context Performance (NEW)

The MTP config (`start-server-27b.ps1`) is NOT suitable for long context. Speed collapses:

| Context | 27B MTP (64K ctx, --fit on) |
|---------|---------------------------|
| 4K+ | 10-17 t/s |

**Root cause**: Context size controls VRAM allocation. At 64K, --fit reserves KV for
full 64K and offloads model layers to CPU = 13 t/s for ALL context sizes.

**Fix**: Drop MTP, use 16K context with -ngl 99 -fit off. All layers fit in VRAM:

| Context | 27B IQ3_XXS 16K ctx |
|---------|---------------------|
| 1.7K | 28.31 t/s |
| 3.3K | 27.51 t/s |
| 5K | 26.66 t/s |
| 8.3K | 26.98 t/s |
| 10K | 26.60 t/s |
| 13.3K | 25.97 t/s |
| 15K | 25.78 t/s |

**Winner for long context**: `start-server-27b-longctx.ps1` — IQ3_XXS, no MTP, 16K ctx, q4_0 KV, -ngl 99.
Stable ~26 t/s across entire 16K context window.

**Why 16K context**: Context size = KV reservation = less VRAM for model layers.
- 16K: 12.4GB VRAM = all layers on GPU = 26 t/s
- 32K: 12.7GB = some layers to CPU = 22 t/s
- 64K: 14.3GB = many layers to CPU = 13 t/s

**KV cache comparison at 64K context (all slow due to offload)**:

| KV Cache | 5K | 10K | 20K | 30K | 35K |
|----------|-----|------|------|------|------|
| q4_0 | 27.1 | 19.8 | 22.2 | 13.2 | - |
| q8_0 | 27.0 | 25.3 | 25.6 | 14.8 | 19.2 |

These speeds are misleading — the 64K ctx reservation already slows everything.
Use 16K ctx instead for real speed.

**iq4_nl KV is terrible**: Only 8 t/s at 5K context — decompression overhead destroys speed.

## 27B vs 35B Final Comparison

| Model | Best Speed | Long Ctx Speed | Quality | Recommendation |
|-------|-----------|----------------|---------|----------------|
| 27B MTP (short ctx, 64K) | 35.49 t/s | collapses at 4K+ | 4/4 tasks | Short conversations only |
| 27B Longctx (no MTP, 16K) | ~29 t/s | ~26 t/s at 15K | 4/4 tasks | Stable long conversations |
| 35B MoE + MTP + ngram | 53.56 t/s | stable at 64k | 5/5 tasks | **Best overall** |
