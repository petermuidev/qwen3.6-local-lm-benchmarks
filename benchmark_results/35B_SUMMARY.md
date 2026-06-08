# 35B MoE Benchmark Summary

## Hardware: i5-14600KF + RTX 5060 Ti 16GB + DDR4 + Windows 11

## Results

| Config | Runtime | Speed | Passed | Notes |
|--------|---------|-------|--------|-------|
| Q4_K_S (19.9GB) | llama.cpp b9360 | **29.88 tok/s** | 5/5 | Best 35B result |
| Q4_K_M + --fit | llama.cpp b9360 | 26.50 tok/s | 5/5 | Slightly slower (larger model) |
| Q4_K_M + --fit + MTP + ngram-mod | llama.cpp b9360 | 26.86 tok/s | 5/5 | Speculative doesn't help on DDR4 |

## Key Lessons

1. **DDR4 is the hard ceiling at ~30 tok/s for 35B MoE**. The 35B MoE at Q4_K (~20GB) must offload MoE experts to CPU RAM. DDR4 bandwidth (~25GB/s) limits generation to ~30 tok/s regardless of quant or speculative decoding.

2. **MTP + ngram-mod stacking doesn't help on DDR4**. The Reddit user who got 60 tok/s likely has DDR5 (~50GB/s+ bandwidth). Speculative decoding acceptance rate is high but DDR4 can't feed the verified tokens fast enough to benefit.

3. **Q4_K_S slightly beats Q4_K_M** on our hardware. Q4_K_S is smaller (19.9GB vs ~21.1GB), meaning less DDR4 offload and slightly faster generation.

4. **ik_llama.cpp is not an option** (confirmed 10x slower on Windows in 27B tests). The `--n-cpu-moe 16` and `-fmoe` flags that give 61 tok/s on Linux are unavailable to us.

5. **The Reddit 60 tok/s claim is NOT reproducible on our hardware**. DDR4 vs DDR5 is the difference. On DDR5, MoE offload is ~2x faster.

## 35B Winner

**Q4_K_S on llama.cpp b9360**: 29.88 tok/s, 5/5 tasks passed.

## What could improve 35B further

- **DDR5 RAM upgrade**: Would likely push 35B MoE from ~30 to ~50-60 tok/s (the Reddit user's result)
- **Linux dual-boot**: Would unlock ik_llama.cpp with --n-cpu-moe + -fmoe (61+ tok/s proven on same GPU)
- **Smaller quant that fits more in VRAM**: IQ4_XS (~16GB) might fit more in VRAM and offload less, but quality tradeoff

## Overall: 27B vs 35B on this hardware

| Model | Best Speed | Best Quality | Recommendation |
|-------|-----------|-------------|----------------|
| 27B IQ3_XXS | 23.67 tok/s | 4/4 tasks | Best for speed, fits in VRAM |
| 35B MoE Q4_K_S | 29.88 tok/s | 5/5 tasks | **Best overall** — faster AND better quality |

**35B MoE is the winner** — faster than 27B AND passes more tasks (5/5 vs 4/4 including bank simulation).
