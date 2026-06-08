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

## 27B vs 35B Final Comparison

| Model | Best Speed | Quality | Context | Recommendation |
|-------|-----------|---------|---------|----------------|
| 27B IQ3_M + MTP | 35.49 tok/s | 4/4 tasks | 64k | Best if you prefer dense model |
| 35B MoE + MTP + ngram | 53.56 tok/s | 5/5 tasks | 64k | **Best overall** — faster AND better quality |
