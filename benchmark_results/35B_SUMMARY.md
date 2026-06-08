# 35B MoE Benchmark Summary

## Hardware: i5-14600KF + RTX 5060 Ti 16GB + DDR4 + Windows 11

## Results

| Config | Runtime | Speed | Passed | Notes |
|--------|---------|-------|--------|-------|
| Q4_K_S vanilla (no fit, no-mmap, cache-ram 0) | llama.cpp b9360 | ~30* / ~49** tok/s | 5/5 | *naive measurement, **server-reported tg speed |
| Q4_K_S + fit on + kv-unified + no-mmproj | llama.cpp b9360 | **46.03 tok/s** | 5/5 | Corrected config, proper speed measurement |
| Q4_K_S + fit + kv-unified + no-mmproj + MTP+ngram | llama.cpp b9360 | **53.56 tok/s** | 5/5 | +16% from speculative decoding |
| Q4_K_S + fit + MTP+ngram + q5_0/q4_1 KV | llama.cpp b9360 | 40.20 tok/s | 5/5 | Lower KV quant hurts generation speed |
| Q4_K_S + fit + MTP+ngram + q8_0/q5_0 KV | llama.cpp b9360 | ~36 tok/s | - | Asymmetric KV slower for generation |
| Q4_K_S + fit + MTP+ngram + 32k ctx | llama.cpp b9360 | ~54 tok/s | - | Faster but can't handle long sessions |

## Key Lessons

1. **Config was the bottleneck, not hardware**. The old config missed `--fit on`, `--kv-unified`, `--no-mmproj`, and had harmful `--no-mmap` and `--cache-ram 0`. Fixing these alone took generation from ~30 to ~46 tok/s.

2. **MTP + ngram-mod stacking adds +16% on top of good config**. With the corrected base (fit on, kv-unified), speculative decoding gives 46 → 53.56 tok/s. Previously it showed no improvement because the base config was already broken.

3. **KV cache quantization for generation ≠ prefill**. The Anbeeld article benchmarks prefill throughput; q4_0/q5_0 match q8_0 there. But for token-by-token generation with MoE CPU offload, lower KV quant adds decompression overhead per token that outweighs VRAM savings. **q8_0/q8_0 remains best for generation speed**.

4. **Asymmetric KV (q8_0/q5_0, q5_0/q4_1) hurts generation on MoE**. Consistently slower than symmetric q8_0. The K/V decompression cost during generation is different from batch prefill.

5. **32k context is faster but impractical**. ~54 tok/s with 32k ctx vs ~53 with 64k, but the small gain isn't worth losing long-context capability. Optimize for 64k stability.

6. **Speed measurement matters**. Dividing `completion_tokens / total_elapsed` includes prompt processing time and understates generation speed by ~40%. Always use the server's `predicted_per_second` from response timings.

## 35B Winner

**Q4_K_S + --fit on + --kv-unified + --no-mmproj + MTP+ngram on llama.cpp b9360**: 53.56 tok/s, 5/5 tasks passed, 64k context stable.

## What could improve 35B further

- **DDR5 RAM upgrade**: Would push MoE offload bandwidth from ~25GB/s to ~50GB/s+
- **Linux dual-boot**: Would unlock ik_llama.cpp with --n-cpu-moe + -fmoe (61+ tok/s proven)
- **Newer llama.cpp build**: b9484+ may have incremental MoE improvements
- **draft-max=1 vs 2**: Could test if single-token speculative has better acceptance rate on our hardware
