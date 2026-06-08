## Configuration Guide — Qwen 3.6 on RTX 5060 Ti 16GB + DDR4 + Windows 11

**Last updated**: 2026-06-08 — after full benchmark overhaul fixing broken configs

---

### Quick Start

| Model | Script | Speed | Context | Quality |
|-------|--------|-------|---------|---------|
| 35B MoE Q4_K_S | `start-server-35b.ps1` | **53.56 t/s avg** (57 t/s multi-turn) | 64k | 5/5 tasks |
| 35B MoE Q4_K_S (no MTP) | `start-server-35b-reddit60.ps1` | **46.03 t/s avg** | 64k | 5/5 tasks |
| 27B Dense IQ3_XXS | `start-server-27b-iq3xxs.ps1` | **23.67 t/s** | 65k | 4/4 tasks |

**Recommendation**: Use `start-server-35b.ps1` — faster AND better quality than 27B.

---

### Production Config: 35B MoE (`start-server-35b.ps1`)

```powershell
llama-server.exe -m Qwen3.6-35B-A3B-UD-Q4_K_S.gguf `
  --jinja --host 127.0.0.1 --port 8080 `
  -t 16 -c 64000 -n 32768 -np 1 `
  -fa on --fit on --kv-unified --no-mmproj `
  -ctk q8_0 -ctv q8_0 `
  --spec-type draft-mtp,ngram-mod `
  --spec-draft-n-max 2 `
  --spec-ngram-mod-n-match 40 --spec-ngram-mod-n-min 0 --spec-ngram-mod-n-max 16
```

**Critical flags explained:**

| Flag | Why it matters |
|------|---------------|
| `--fit on` | Auto GPU/CPU tensor split — #1 most important flag. Without this, generation is ~30 t/s instead of ~46 t/s |
| `--kv-unified` | Unified KV cache saves VRAM, less DDR4 offload needed |
| `--no-mmproj` | Skip multimodal projector (not needed for text), saves VRAM |
| `-fa on` | Flash Attention — ON by default in newer builds but explicit for safety |
| `-ctk q8_0 -ctv q8_0` | q8_0 KV is fastest for generation. Lower quants (q5_0, q4_1) save VRAM but hurt generation speed on MoE |
| `--spec-type draft-mtp,ngram-mod` | MTP + ngram speculative decoding — +16% over base (46→53 t/s) |
| `--kv-unified` | Required for prompt caching to work properly |

**Flags we do NOT use (and why):**

| Flag | Why NOT to use |
|------|---------------|
| `--no-mmap` | Forces full model into RAM, hurts MoE expert paging. Let OS manage via mmap |
| `--cache-ram 0` | Disables prompt caching, hurts multi-turn speed. --fit manages VRAM automatically |
| `--no-warmup` | Only saves startup time, minor — not worth the risk |
| `-rtr` | Prevents GPU offload of CPU-stored tensors, hurts MoE performance |

---

### What Was Wrong Before (Lessons Learned)

See `benchmark_results/35B_LESSONS_LEARNED.md` for the full list. Key mistakes:

1. **Missing `--fit on`** — caused ~30 t/s instead of ~46 t/s (53% loss from one flag)
2. **`--no-mmap`** — hurt MoE expert paging
3. **`--cache-ram 0`** — disabled prompt caching unnecessarily
4. **Wrong speed measurement** — `completion_tokens / total_elapsed` includes prompt time, understates generation by ~40%. Use `timings.predicted_per_second`
5. **"DDR4 ceiling at ~30 t/s"** — wrong conclusion from broken config. Real ceiling is ~45-50 t/s sustained
6. **"MTP doesn't help on DDR4"** — wrong. MTP gives +16% on correct base config

---

### KV Cache Quantization (Tested, Not Theoretical)

Based on Anbeeld benchmarks + our own generation testing:

| KV Cache | Generation Speed | VRAM Savings | Quality | Verdict |
|----------|-----------------|-------------|---------|---------|
| q8_0/q8_0 | **53.56 t/s** | Baseline | 94.61% tail prec | **Best for generation** |
| q5_0/q4_1 | 40.20 t/s | ~19% saved | 92.65% tail prec | Slower — decompression overhead hurts MoE |
| q8_0/q5_0 | ~36 t/s | ~10% saved | 93.69% tail prec | Even asymmetric hurts generation |

**Conclusion**: q8_0/q8_0 wins for generation speed. The Anbeeld article benchmarks prefill throughput where q4_0 ≈ q8_0, but generation is different — per-token KV decompression adds latency that compounds with MoE CPU offload.

---

### What Doesn't Work on This Hardware

| Approach | Result | Why |
|----------|--------|-----|
| ik_llama.cpp (any build) | 2 t/s or crash | AVX2 build is 10x slower than upstream. AVX512 crashes on Raptor Lake (partial AVX512) |
| TurboQuant / atomic-llama-cpp | Never tested | Different fork, requires its own build. Low priority |
| Lower KV quant for MoE generation | Slower | Decompression overhead > VRAM savings |
| 32k context for speed | ~54 t/s but useless | Can't handle long sessions. 64k is the right tradeoff |

---

### What Could Improve Further

| Upgrade | Expected Impact | Feasibility |
|---------|----------------|-------------|
| DDR5 RAM | ~30→50+ t/s MoE offload bandwidth | Hardware upgrade |
| Linux dual-boot | Unlocks ik_llama.cpp (61+ t/s proven) | OS change |
| Newer llama.cpp build (b9484+) | Possible incremental MoE gains | Easy to test |
| draft-max=1 vs 2 | Possibly higher acceptance rate | Easy to test |
| Smaller 35B quant (IQ4_XS ~16GB) | More VRAM fit, less offload | Need model file |

---

### Recommended Sampling (Qwen 3.6)

```powershell
--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --presence-penalty 1.25
```

This is Reddit consensus for Qwen 3.6 quality. Our benchmark scripts include these by default.

---

### File Reference

| File | Purpose |
|------|---------|
| `start-server-35b.ps1` | 35B MoE production (MTP + ngram, 64k ctx) |
| `start-server-35b-reddit60.ps1` | 35B baseline (no MTP, for comparison) |
| `start-server-27b-iq3xxs.ps1` | 27B dense production |
| `stop-server.ps1` | Kill running server |
| `benchmark-35b.py` | 35B benchmark (5 tasks, proper speed measurement) |
| `benchmark-27b.py` | 27B benchmark (4 tasks, proper speed measurement) |
| `benchmark_results/35B_SUMMARY.md` | 35B benchmark results |
| `benchmark_results/27B_SUMMARY.md` | 27B benchmark results |
| `benchmark_results/35B_LESSONS_LEARNED.md` | Detailed mistakes and methodology fixes |

### Model Files

```powershell
# 35B MoE (production)
hf download unsloth/Qwen3.6-35B-A3B-MTP-GGUF Qwen3.6-35B-A3B-UD-Q4_K_S.gguf --local-dir models\Qwen3.6-35B-A3B-MTP-GGUF

# 27B Dense (production)
hf download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-UD-IQ3_XXS.gguf --local-dir models\Qwen3.6-27B-GGUF
```
