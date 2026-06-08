# 35B MoE Optimization — Lessons Learned & Mistakes

## What I Got Wrong (the hard list)

### 1. Missing `--fit on` — THE critical mistake

I benchmarked the 35B MoE **without `--fit on`** and concluded:
> "DDR4 is the hard ceiling at ~30 tok/s for 35B MoE"

**This was completely wrong.** The ~30 tok/s was a broken config, not a hardware ceiling. The Reddit user's config had `--fit on`. I copied other flags but missed this one. With `--fit on`, generation jumped from ~30 to ~46 tok/s — a **53% improvement** from a single missing flag.

**Why I missed it**: The vanilla script (`start-server-q4ks-vanilla.ps1`) was meant as a "baseline without MTP" and I assumed `--fit` was only needed for MTP. Wrong — `--fit` controls the GPU/CPU tensor split for the base model too. Without it, llama.cpp dumps more tensors to CPU than necessary.

### 2. `--no-mmap` — Added for no reason, hurt performance

I added `--no-mmap` to the vanilla config. This forces the entire model to be read into RAM instead of memory-mapped. For MoE models where experts are paged in/out, mmap is actually beneficial — the OS can page experts efficiently. `--no-mmap` prevented this optimization.

**Why I added it**: Copied from another config without understanding what it does for MoE specifically. It's sometimes useful for avoiding slow disk reads on spinning drives, but we have SSD.

### 3. `--cache-ram 0` — Disabled prompt caching for no benefit

This disables prompt caching entirely. The Reddit 60 tok/s config did NOT have this flag. Prompt caching helps with multi-turn conversations (our 57.49 tok/s result used it). I disabled it thinking it would save VRAM, but `--fit` handles VRAM allocation automatically.

**Why I added it**: Copied from a different config that used it for a specific reason (preventing cache from eating VRAM on small GPUs). With `--fit on`, llama.cpp manages this automatically.

### 4. Wrong speed measurement — Understated generation speed by ~40%

My benchmark calculated speed as:
```python
tps = completion_tokens / total_elapsed  # WRONG
```

This includes prompt processing time (prefill) in the denominator. For a 200-token completion with 5s prompt + 4s generation:
- Wrong: 200/9 = 22.2 tok/s
- Right: 200/4 = 50 tok/s (server's `predicted_per_second`)

I used this wrong measurement to draw major conclusions about hardware ceilings and MTP effectiveness. **Every speed number in the old summary was wrong by ~40%.**

**Fix**: Use `timings.predicted_per_second` from the server response, which measures generation speed only.

### 5. "MTP doesn't help on DDR4" — Wrong conclusion from broken base

I concluded:
> "MTP + ngram-mod stacking doesn't help on DDR4"

This was false. MTP gave **+16%** (46 → 53.56 tok/s) once the base config was correct. The reason MTP appeared useless before: it was running on top of a broken config that was already bottlenecked by missing `--fit`. MTP can't speed up what's already crippled by bad tensor placement.

### 6. "DDR4 bandwidth ceiling at ~30 tok/s" — Entire thesis was wrong

The entire narrative that DDR4 ~25GB/s bandwidth was the hard ceiling was built on broken benchmarks. Real generation speed on DDR4 is **46-57 tok/s** depending on context length and conversation type. The ~30 tok/s was a config error, not a hardware limit.

The actual DDR4 ceiling exists but is higher — around 45-50 tok/s for sustained long generation with growing KV cache. Short/multi-turn generation can exceed this because less KV data needs to traverse DDR4 per token.

### 7. Applied Anbeeld prefill benchmarks to generation — Wrong domain

The Anbeeld article shows q4_0 and q8_0 KV cache have similar **prefill** throughput (~850 tok/s). I assumed this meant they'd be similar for **generation** too. They're not:

| KV Cache | Prefill (article) | Generation (our bench) |
|----------|-------------------|----------------------|
| q8_0/q8_0 | 851 tok/s | **53.56 tok/s** |
| q5_0/q4_1 | 848 tok/s | **40.20 tok/s** |
| q8_0/q5_0 | 847 tok/s | **~36 tok/s** |

Prefill processes all KV in parallel batches — quant type barely matters. Generation processes one token at a time, reading the full KV cache each step — lower quant means decompression overhead per token that compounds with MoE CPU offload latency.

**Lesson**: Prefill benchmarks ≠ generation benchmarks. Always measure the workload you actually care about.

### 8. Didn't systematically compare flags with the Reddit config

The user told me they get ~50 tok/s. Instead of immediately doing a line-by-line flag comparison with the known-working Reddit config, I speculated about hardware differences and quant sizes. The fix was obvious — match the flags that were proven to work.

---

## What Actually Matters for 35B MoE on 16GB VRAM

### The flag hierarchy (impact ranked)

| Priority | Flag | Impact | Why |
|----------|------|--------|-----|
| 1 | `--fit on` | +53% | Auto GPU/CPU split — keeps as much as possible in VRAM |
| 2 | `--kv-unified` | +5-10% | Unified KV saves VRAM, less DDR4 offload |
| 3 | `--no-mmproj` | +3-5% | Skip unused multimodal projector, saves VRAM |
| 4 | Remove `--no-mmap` | +3-5% | Allow OS to page MoE experts efficiently |
| 5 | Remove `--cache-ram 0` | +5-10% (multi-turn) | Enable prompt caching for conversation reuse |
| 6 | MTP + ngram-mod | +16% (on good base) | Speculative decoding with high acceptance rate |
| 7 | KV type q8_0/q8_0 | Baseline | Lower KV quants hurt generation despite saving VRAM |

### What doesn't matter

| Flag / Approach | Result | Why |
|-----------------|--------|-----|
| ik_llama.cpp on Windows | 10x slower | AVX2 is crippled, AVX512 crashes on Raptor Lake |
| Lower KV quant (q5_0, q4_1) | Slower | Decompression overhead per token outweighs VRAM savings |
| 32k context | Slightly faster | Not worth losing long-context capability |
| `-rtr` flag | Avoid | Prevents GPU offload of CPU tensors |

---

## Methodology Rules Going Forward

1. **Always match known-working configs first** before speculating about hardware limits
2. **Measure generation speed separately from prompt processing** — use `predicted_per_second`
3. **Test one change at a time** — the old config had 3 problems masked as 1 (missing fit + no-mmap + cache-ram 0)
4. **Don't generalize prefill benchmarks to generation** — different compute patterns
5. **Don't assume hardware is the bottleneck** until the config is proven correct
6. **Benchmark with realistic multi-turn workloads**, not just short single prompts
7. **When user reports different speed than benchmarks, compare configs systematically** — don't dismiss their result
