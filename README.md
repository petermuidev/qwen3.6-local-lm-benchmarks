# Qwen3.6 Local LLM Benchmarks

Benchmarks, configurations, and case study for running Qwen3.6 models locally on **RTX 5060 Ti 16GB + DDR4 RAM + Windows 11**.

## Key Finding

On DDR4 bandwidth-starved hardware (~38 GB/s), a smaller **dense model** (27B IQ3_XXS at ~26 tok/s) produces **better code** than a bigger **MoE model** (35B-A3B Q4_K_S at ~33 tok/s). Speed is misleading — the dense model activates all 27B parameters per token vs MoE's 3.6B/35B, giving more reasoning capacity per step.

**VERIFIED (July 2026)**: ik_llama.cpp with `--n-cpu-moe 20` on our RTX 5060 Ti 16GB + DDR4 gives **43 tok/s at 64K context** (upstream was ~5-6 tok/s at same context). See [BENCHMARK_JULY2026.md](BENCHMARK_JULY2026.md) for full results.

**NEW (mid-July 2026)**: llama.cpp b10054 + DFlash + ngram-mod spec-decoding stack on 27B dense gives **~6x on multi-turn coding** per Reddit research (u/FantasticNature7590, RTX 6000 PRO). On our hardware: 27B DFlash server boots, 55% DFlash draft acceptance on single-turn, 13.35 tok/s with spec active. Multi-turn speedup will be higher as n-gram cache fills. 35B MoE + ngram-mod server also set up — ngram-mod is free (host RAM) and kicks in on multi-turn sessions.

**Luce Spark** (untested) could push this further — shrinks 35B from 20.5 GiB to 13.3 GiB by keeping only active MoE experts on GPU. See [REDDIT_SYNTHESIS.md](REDDIT_SYNTHESIS.md).

| Model | Speed | Context | Sudoku | Bank simulation | Tokens |
|-------|-------|---------|--------|-----------------|--------|
| 27B dense IQ3_XXS (upstream) | ~26 tok/s | 32K | Correct | **Correct** | Few |
| 27B dense IQ3_XXS + DFlash+ngram (b10054) | ~13 tok/s single-turn, ~6x multi-turn | 32K | ? | ? | ? |
| 35B-A3B MoE Q4_K_M (ik_llama, n-cpu-moe 20) | **~43 tok/s** | 64K | ? | ? | ? |
| 35B-A3B MoE Q4_K_M + ngram-mod (b10054) | ~25 tok/s single-turn, higher multi-turn | 64K | ? | ? | ? |
| 35B-A3B MoE Q4_K_M (ik_llama, n-cpu-moe 16) | **~49 tok/s** | 48K max | ? | ? | ? |

## Quick Start

### NEWEST: Qwen3.8-27B + MTP — ~50 t/s at 94K context (Aug 2026)

```powershell
.\start-server-38b.ps1
```

Build: llama.cpp b10437 (CUDA 12.4). Model: Qwen3.8-27B UD-IQ3_XXS (11.9GB, MTP weights embedded). Spec: `draft-mtp` draft-max=3. KV: q4_0. All layers on GPU. `reasoning_effort=medium` (xhigh over-thinks). Chat template embedded in GGUF. Replicates HF discussion #26 — same GPU.

**Env overrides**: `LLAMA_CONTEXT` (default 94208), `LLAMA_PORT` (8080), `LLAMA_HOST`, `LLAMA_THREADS`, `LLAMA_DRAFT_MAX` (3).

**Verified on our hardware (Aug 2026)**:
- **GPU warmup is real**: first request after boot ~15-30 t/s; consecutive back-to-back runs climb to **48-50 t/s** (measured 32 → 42 → 50 → 48 on identical prompts). Fire 2-3 small prompts before benchmarking or heavy work.
- Cold one-shot (space-shooter prompt, raw API): 15 t/s. Warm sustained: 48-50 t/s.
- MTP gives ~2x over no-MTP baseline (10.5 → 21 t/s cold).
- **Draft-max tradeoff**: draft-max=3 matches discussion speed but can corrupt tool-call JSON (same issue as Qwen3.6). Use `$env:LLAMA_DRAFT_MAX="1"` for opencode/pi agent sessions.
- **pi CLI**: registered as `local/qwen3.8-27b` (thinking on, 94K ctx). Switch with `/models` in pi.

### BEST for opencode coding — 27B dense + DFlash + ngram stack (NEW, ~6x on multi-turn)

```powershell
.\start-server-27b-dflash.ps1
```

Build: llama.cpp b10054 (CUDA 12.4). Model: Unsloth UD-IQ3_XXS (11.17GB) + Alittlehammmer DFlash-Q8_0 draft (1.8GB). Spec: `draft-dflash,ngram-mod,ngram-map-k4v`, `--fit on`, KV: q4_0, 32K ctx, `-rea off`. Best for opencode coding agent (multi-turn sessions where n-gram cache fills).

### BEST for long context — 35B MoE + ngram-mod (NEW, PR #25545 CPU-offload gains)

```powershell
.\start-server-35b-ngram.ps1
```

Build: llama.cpp b10054 (CUDA 12.4, includes PR #25545 3x CPU-offload speedup). Model: Q4_K_M (19.7GB). Spec: `ngram-mod` (free on VRAM, drafts from host RAM). `--n-cpu-moe 20`, KV: q4_0, 64K ctx. Best for pi CLI long-context API work.

### Best for coding — 27B dense IQ3_XXS (~26 tok/s, upstream llama.cpp)

```powershell
.\start-server-27b-iq3xxs.ps1
```

Model: Unsloth UD-IQ3_XXS (11.17GB), KV: q4_0, prompt cache OFF, no MTP.

### Fastest for casual use — 35B-A3B MoE Q4_K_S (~33 tok/s, upstream llama.cpp)

```powershell
.\start-server-q4ks-vanilla.ps1
```

Model: Unsloth UD-Q4_K_S (19.9GB), KV: q8_0, prompt cache OFF, no MTP.

### BEST (proven fallback): ik_llama.cpp + 35B MoE (~43 tok/s at 64K context)

```powershell
.\start-server-ik-35b-moe-ncpumoe20.ps1
```

Model: Q4_K_M (19.7GB), KV: q4_0, `--n-cpu-moe 20`, all dense layers on GPU, MoE experts on CPU.

### ik_llama.cpp + 35B MoE (~49 tok/s at up to 48K context)

```powershell
$env:LLAMA_CONTEXT = "49152"
.\start-server-ik-35b-moe-ncpumoe20.ps1
```

Uses `--n-cpu-moe 16` (fewer experts on CPU = faster gen, but KV overflows at 48K+).

### Previous configs (upstream llama.cpp)

### NEW: TurboQuant config (alternative fork)

```powershell
.\start-server-tq-35b-moe-nextn.ps1
```

Different runtime fork (atomic-llama-cpp-turboquant) with TurboQuant KV + NextN speculative decoding. +28-36% on 35B MoE.

### Stop server

```powershell
.\stop-server.ps1
```

## Spec Decoding Stack (mid-July 2026 research)

Based on Reddit research on r/LocalLLaMA — see [REDDIT_SYNTHESIS.md](REDDIT_SYNTHESIS.md) for full sources.

| Method | Speedup | VRAM cost | Best for |
|--------|---------|-----------|----------|
| Baseline | 1.0x | — | — |
| MTP (existing) | 1.45-2.7x | ~300MB draft + draft KV | Chat, creative, varied prompts |
| DFlash | 2.2-3.7x | ~5.5GB draft model | Coding, JSON, structured output |
| DFlash + ngram-mod | **5.68x** | ~0GB extra (host RAM) | Multi-turn coding, editing own code |
| DFlash + ngram-mod + ngram-map-k4v | **6.01x** | ~0GB extra | Same — marginally better than mod alone |

Key flags (llama.cpp b10054+):
```
--spec-type draft-dflash,ngram-mod,ngram-map-k4v
--spec-draft-n-max 15
--spec-ngram-mod-n-match 24    # 24-token lookup key
--spec-ngram-mod-n-min 48      # draft 48 tokens
--spec-ngram-mod-n-max 64      # up to 64
--spec-ngram-map-k4v-size-n 12
--spec-ngram-map-k4v-size-m 48
--spec-ngram-map-k4v-min-hits 1
```

**Key findings from Reddit (u/FantasticNature7590, RTX 6000 PRO, July 2026):**
- 18-turn coding session: 321.5 vs 53.5 tok/s = 6.01x with full stack
- Maintenance turns (editing existing code): 385 tok/s, 7.5x baseline
- n-gram advantage GROWS with session (more context = more to copy); baseline decays
- On varied one-shot prompts n-gram adds nothing (cache starts empty)
- n-gram drafters are literally free on GPU (tables in host RAM)
- Lossless on MATH-500 (440/500 vs 435/500) and LiveCodeBench
- DFlash acceptance best at temp=0 (greedy)

**On our hardware (RTX 5060 Ti 16GB + DDR4):**
- 27B IQ3_XXS (11.17GB) + DFlash Q8_0 (1.8GB) + KV q4_0 fits in 16GB VRAM with `--fit on` (auto GPU/CPU split)
- 35B MoE (19.7GB) + DFlash (5.5GB) does NOT fit — use ngram-mod only (free VRAM)
- The `dflash requires ctx_other to be set` warning during memory fitting is benign — DFlash still activates (verified via `draft_n > 0` in timings)

## Models Required

### Upstream llama.cpp models (Unsloth)

| Model | Repo | File | Size |
|-------|------|------|------|
| 27B IQ3_XXS | `unsloth/Qwen3.6-27B-GGUF` | `Qwen3.6-27B-UD-IQ3_XXS.gguf` | 11.17 GB |
| 35B-A3B Q4_K_S | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` | `Qwen3.6-35B-A3B-UD-Q4_K_S.gguf` | 19.9 GB |
| 35B-A3B Q4_K_M | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` | `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` | 21.1 GB |
| Qwen3.8 27B IQ3_XXS | `unsloth/Qwen3.8-27B-GGUF` | `Qwen3.8-27B-UD-IQ3_XXS.gguf` | 11.9 GB |

### ik_llama.cpp models (additional)

| Model | Repo | File | Size |
|-------|------|------|------|
| 27B MTP Q8_0 | `Radamanthys11/Qwen3.6-27B-MTP-Q8_0-GGUF` | `Qwen3.6-27B-MTP-Q8_0.gguf` | ~15.3 GB |

### TurboQuant models (AtomicChat)

| Model | Repo | File | Size |
|-------|------|------|------|
| 35B-A3B TQ4_1S MTP | `AtomicChat/Qwen3.6-35B-A3B-UDT-MTP-GGUF` | `Qwen3.6-35B-A3B-UDT-MTP-TQ4_1S.gguf` | ~15 GB |

Place files in `models/` subdirectories. Download commands in [CONFIG_GUIDE.md](CONFIG_GUIDE.md).

## Opencode Integration

Both models are configured as a local provider in `~/.config/opencode/opencode.json`:

```json
{
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local llama-server",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "local-dev-key-001"
      },
      "models": {
        "qwen3.6-27b-iq3xxs": {
          "name": "Qwen3.6 27B IQ3_XXS (local, ~26 tok/s)",
          "limit": { "context": 65536, "output": 4096 }
        },
        "qwen3.6-35b-q4ks": {
          "name": "Qwen3.6 35B-A3B Q4_K_S (local, ~33 tok/s)",
          "limit": { "context": 65536, "output": 4096 }
        }
      }
    }
  }
}
```

Switch models with `/models` in opencode. Start the matching llama-server first.

## Key Lessons (updated July 2026 with Luce Spark + 5080 findings)

1. **ik_llama.cpp is the biggest single fix** — 26→61 tok/s on same hardware with `--n-cpu-moe 16 -fmoe`. See [CONFIG_GUIDE.md](CONFIG_GUIDE.md) for build instructions.
2. **Luce Spark could eliminate DDR4 offload entirely** — 35B MoE shrinks from 20.5→13.3 GiB by keeping only active experts on GPU. If it works, this is the biggest upgrade for 16GB VRAM cards.
3. **MTP is net-negative for 35B MoE on 16GB VRAM** — RTX 5080 16GB evidence: MTP overhead reduces context window and acceptance rate is too low to compensate. This only applies to 16GB; 12GB and 24GB cards still benefit.
4. **DDR4 bandwidth is the bottleneck** — Model fit > quant quality. IQ3_XXS (11.17GB) beats IQ4_XS (14.38GB) because it fits in VRAM.
5. **Prompt cache kills DDR4 performance** — `--cache-ram 0` prevents progressive speed collapse.
6. **q4_0 KV is lossless but not always faster** — Best for dense (frees VRAM), worse for hybrid MoE.
7. **`--fit` auto beats manual MoE offload on upstream** — 36.1 vs 23.1 tok/s. But ik_llama.cpp `--n-cpu-moe 16` beats both at 61 tok/s.
8. **`--fit-target 1536` may be better than `--fit`** — From RTX 5080 benchmarks at 131K context.
9. **Increase `-ub` for better prompt processing** — `-ub 2048` or higher with `--n-cpu-moe` gives huge prefill speedup.
10. **Dense > MoE for coding on upstream** — All 27B params active vs 3.6B/35B. With ik_llama.cpp or Luce Spark MoE speed gains, re-benchmark quality.
11. **Disable thinking** — Send `chat_template_kwargs.enable_thinking: false`.
12. **Only one llama-server at a time** — Multiple servers destabilize the system.
13. **Do NOT use `-rtr` with `--n-cpu-moe`** — Breaks hybrid CPU/GPU MoE offload in ik_llama.cpp.
14. **Do NOT use Unsloth `_XL` GGUF with ik_llama.cpp** — f16 tensors break it.
15. **Short-context benchmarks are misleading** — 80 tok/s at 512 tokens drops to 30-40 at 100K. Always benchmark at realistic context lengths.

## Hardware

| Component | Spec |
|-----------|------|
| GPU | RTX 5060 Ti 16GB (448 GB/s) |
| CPU | Intel i5-14600KF (20 threads) |
| RAM | DDR4-2400/2667 (~38 GB/s) |
| OS | Windows 11 Pro |

## Full Details

- [CONFIG_GUIDE.md](CONFIG_GUIDE.md) — Configuration gap analysis, ik_llama.cpp build instructions, exact commands
- [CASE_STUDY.md](CASE_STUDY.md) — Complete case study with all benchmarks, tests, and analysis
- [SUMMARY.md](SUMMARY.md) — Technical summary with configuration history and research notes

## License

Configs and documentation — use freely. Model files subject to Unsloth/Qwen license terms.