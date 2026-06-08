## Configuration Guide — Qwen 3.6 on RTX 5060 Ti 16GB + DDR4 + Windows 11

**Last updated**: 2026-06-08 — added chat template fix, 32K context for opencode, MTP draft-max tuning

---

### Quick Start

| Model | Script | Speed | Context | Quality | Best For |
|-------|--------|-------|---------|---------|----------|
| 35B MoE Q4_K_S | `start-server-35b.ps1` | **53.56 t/s avg** (57 t/s multi-turn) | 64k | 5/5 tasks | Best overall |
| 35B MoE Q4_K_S (no MTP) | `start-server-35b-reddit60.ps1` | **46.03 t/s avg** | 64k | 5/5 tasks | Baseline comparison |
| 27B Dense IQ3_M + MTP | `start-server-27b.ps1` | **~28 t/s** short, **~30 t/s** opencode | 32k | 4/4 tasks | opencode/coding agent |
| 27B Dense IQ3_XXS (raw API) | `start-server-27b-longctx.ps1` | **~26 t/s** stable to 15K | 16k | 4/4 tasks | Raw API long context |

*27B MTP with 32K ctx is best for opencode — opencode auto-compacts at ~10-15K anyway, so 64K KV reservation is wasted VRAM.
Use longctx variant only for raw API use where you send full accumulated context.

**Recommendation**: For opencode, use `start-server-27b.ps1`. For raw API, use `start-server-35b.ps1`.

---

### Production Config: 27B Long Context (`start-server-27b-longctx.ps1`)

```powershell
llama-server.exe -m Qwen3.6-27B-UD-IQ3_XXS.gguf `
  --jinja --host 127.0.0.1 --port 8080 `
  -t 16 -c 16384 -n 32768 -np 1 `
  -ngl 99 -fit off -fa on --kv-unified --no-mmproj `
  -ctk q4_0 -ctv q4_0
```

**Why this config for long context:**

| Choice | Why |
|--------|-----|
| No MTP | Draft cache (~300MB) steals VRAM. MTP collapses to 10 t/s at 4K+ |
| IQ3_XXS (11.2GB) | 800MB more VRAM headroom than IQ3_M |
| 16K context | KEY: smaller ctx = less KV reservation = more layers on GPU. 64K ctx = 13 t/s, 16K ctx = 26 t/s |
| `-ngl 99 -fit off` | All layers on GPU at 16K. Total ~12.4GB fits VRAM. `--fit on` over-reserves KV at 64K |
| q4_0 KV | At 16K ctx, q4_0 keeps total ~12.4GB. q8_0 would push to ~13.5GB and spill layers |

**27B Long Context Speed (benchmarked):**

| Context | Speed |
|---------|-------|
| 1.7K | 28.31 t/s |
| 3.3K | 27.51 t/s |
| 5K | 26.66 t/s |
| 8.3K | 26.98 t/s |
| 10K | 26.60 t/s |
| 13.3K | 25.97 t/s |
| 15K | 25.78 t/s |

Stable ~26 t/s across entire 16K context window. No collapse like MTP config.

**Why not 64K context?**

| Context Size | VRAM Used | Speed | Layers on GPU |
|-------------|-----------|-------|---------------|
| 16K | 12.4GB | 26 t/s | All |
| 32K | 12.7GB | 22 t/s | Most |
| 64K | 14.3GB | 13 t/s | Few (KV offload) |

Context size directly controls how much VRAM is reserved for KV cache. More reservation = fewer model layers on GPU = slower generation.

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
4. **Wrong speed measurement** — `completion_tokens / total_elapsed` includes prompt time, understates generation by ~40%. Use `timelines.predicted_per_second`
5. **"DDR4 ceiling at ~30 t/s"** — wrong conclusion from broken config. Real ceiling is ~45-50 t/s sustained
6. **"MTP doesn't help on DDR4"** — wrong. MTP gives +16% on correct base config
7. **Missing chat template** — MTP gguf (froggeric) has no embedded chat_template. Without `--chat-template-file`, the model outputs XML-style `<function=...>` tool calls instead of OpenAI JSON `tool_calls`. This completely broke opencode tool usage. Fix: `--chat-template-file models\Qwen3.6-27B-MTP-GGUF\templates\chat_template.jinja`
8. **64K context for opencode is wasteful** — opencode auto-compacts at ~10-15K tokens. 64K context reserves ~4.6GB KV VRAM that's never used, pushing model layers to CPU/DDR4. 32K context reserves ~2.3GB KV, model stays on GPU, generation goes from ~15 t/s to ~30 t/s
9. **draft-max=3 breaks tool call JSON** — With draft-max=3, MTP speculates 3 tokens ahead. If any draft token in the middle of a JSON tool call is rejected, the output structure breaks. draft-max=1 is safer for structured output with minimal speed loss (~30 t/s vs ~28 t/s with draft-max=3 at 32K ctx)
10. **Context limit mismatch causes compaction storms** — If opencode config says 64K but server only has 16K (longctx running), every request over 16K fails, triggers compaction, retries. Result: 7 compactions in 29 min, each wasting 20-77 seconds. Match the opencode context limit to the actual server `-c` value

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
| Lower KV quant for MoE generation | Slower | Decompression overhead > VRAM savings |
| iq4_nl KV cache (27B dense) | 8 t/s at 5K | Massive decompression overhead, worse than q4_0 and q8_0 |
| 64K context for 27B in opencode | ~15 t/s, constant compaction | Wasted KV reservation pushes layers to CPU. opencode compacts at ~10-15K anyway |
| MTP without chat template | Tool calls broken | Model outputs XML `<function=...>` instead of JSON `tool_calls` |
| draft-max=3 with tool calls | JSON corruption | Rejected speculative tokens break structured output mid-generation |

---

### What Could Improve Further

| Upgrade | Expected Impact | Feasibility |
|---------|----------------|-------------|
| DDR5 RAM | ~30→50+ t/s MoE offload bandwidth | Hardware upgrade |
| Linux dual-boot | Unlocks ik_llama.cpp (61+ t/s proven) | OS change |
| Newer llama.cpp build (b9484+) | Possible incremental MoE gains | Easy to test |
| Smaller 35B quant (IQ4_XS ~16GB) | More VRAM fit, less offload | Need model file |
| Chat template in gguf metadata | Eliminates need for --chat-template-file flag | Repack model file |

---

### Recommended Sampling (Qwen 3.6)

```powershell
--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 --presence-penalty 1.25
```

This is Reddit consensus for Qwen 3.6 quality. Our benchmark scripts include these by default.

---

### Critical Flags for opencode (27B MTP)

These three flags are required for opencode to work correctly with the 27B MTP model. Without any one of them, tool calls break or speed collapses:

| Flag | What it does | What breaks without it |
|------|-------------|----------------------|
| `--chat-template-file ...chat_template.jinja` | Enables JSON tool_calls format | Model outputs XML `<function=...>` — opencode can't parse tool calls |
| `-c 32000` (not 64000) | Smaller KV reservation, more VRAM for model layers | 64K reserves 4.6GB KV (wasted), layers go to CPU, ~15 t/s instead of ~30 t/s |
| `-rea off` | Disables thinking mode | Qwen 3.6 thinking returns empty `content` field — opencode sees empty response |

---

### File Reference

| File | Purpose |
|------|---------|
| `start-server-35b.ps1` | 35B MoE production (MTP + ngram, 64k ctx) |
| `start-server-35b-reddit60.ps1` | 35B baseline (no MTP, for comparison) |
| `start-server-27b.ps1` | 27B dense opencode (MTP, 32K ctx, chat template, ~30 t/s) |
| `start-server-27b-longctx.ps1` | 27B dense long-context (no MTP, ~25 t/s at 20K) |
| `stop-server.ps1` | Kill running server |
| `benchmark-35b.py` | 35B benchmark (5 tasks, proper speed measurement) |
| `benchmark-27b.py` | 27B benchmark (4 tasks, proper speed measurement) |
| `benchmark_results/35B_SUMMARY.md` | 35B benchmark results |
| `benchmark_results/27B_SUMMARY.md` | 27B benchmark results |
| `benchmark_results/35B_LESSONS_LEARNED.md` | Detailed mistakes and methodology fixes |
| `benchmark_results/27B_LESSONS_LEARNED.md` | 27B mistakes and long-context findings |

### Model Files

```powershell
# 35B MoE (production)
hf download unsloth/Qwen3.6-35B-A3B-MTP-GGUF Qwen3.6-35B-A3B-UD-Q4_K_S.gguf --local-dir models\Qwen3.6-35B-A3B-MTP-GGUF

# 27B Dense MTP (for opencode — includes chat template)
hf download froggeric/Qwen3.6-27B-MTP-GGUF Qwen3.6-27B-IQ3_M-mtp.gguf --local-dir models\Qwen3.6-27B-MTP-GGUF
# Chat template (REQUIRED — not embedded in gguf):
# Already in models\Qwen3.6-27B-MTP-GGUF\templates\chat_template.jinja

# 27B Dense LongCtx (for raw API)
hf download unsloth/Qwen3.6-27B-GGUF Qwen3.6-27B-UD-IQ3_XXS.gguf --local-dir models\Qwen3.6-27B-GGUF
```
