## Summary

This setup is for running `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` with `llama.cpp b9360` on this Windows machine.

## What happened

- Early testing was invalid because there were stale `llama-server` processes left running.
- At one point two servers were running at once. Any MTP on/off comparison from that period is not trustworthy.
- Another issue was request format: the model kept writing into `reasoning_content` and leaving `content` empty.

## What fixed it

- Kill all old `llama-server.exe` processes before testing.
- Run only one server instance at a time.
- For plain chat requests, send thinking control as top-level:

```json
{
  "chat_template_kwargs": {
    "enable_thinking": false
  }
}
```

- Do not rely on `reasoning: "off"` or `reasoning_budget: 0` for this setup. Those did not fix the issue here.

## Known good result

- One clean server on `127.0.0.1:8080`
- Simple prompt: `What is 2+2? Reply with one word only.`
- Valid response:
  - `content = "Four"`
  - `reasoning_content = null`
  - MTP draft: draft_n=2, draft_n_accepted=2 (100% acceptance)

## Current recommended config

- **35B-A3B MoE (no MTP)**: Use `start-server-q4ks-vanilla.ps1` — MTP gives only +2.9%, not worth complexity
  - Model: Unsloth UD-Q4_K_S (19.9GB), KV: q8_0, prompt cache OFF (--cache-ram 0)
  - Vanilla baseline: 33.0 tok/s benchmark avg
  - q4_0 KV tested: 31.84 tok/s — slower than q8_0 for MoE (hybrid has tiny KV already)
- **27B dense IQ3_XXS**: Use `start-server-27b-iq3xxs.ps1` — best 27B config for 16GB DDR4
  - Model: Unsloth UD-IQ3_XXS (11.17GB), KV: q4_0, prompt cache DISABLED (--cache-ram 0)
  - Sustained: ~26 tok/s (tasks 2-3 average), first task slower due to no warmup
  - Passes all coding tests. Better code quality than 35B-A3B MoE.

## Current server behavior

- Plain chat works when `chat_template_kwargs.enable_thinking=false` is sent at the top level.
- Earlier benchmark results from the broken multi-server state should be ignored.

## Optimized MTP benchmark (2026-06-01)

Using `start-server-optimized.ps1` with Reddit/community-researched settings:

| Setting | Original | Optimized |
|---------|----------|-----------|
| spec-draft-n-max | 3 | 2 (Unsloth recommended, no determinism bug #23302) |
| spec-draft-p-min | 0 | 0.75 (NVIDIA forum, boosts acceptance ~72%→81%) |
| -ngl | 26 (manual) | removed (let --fit auto-determine) |
| --n-cpu-moe | 16 (manual) | removed (let --fit auto-determine) |
| --fit | on (conflicted!) | on + target 1536M (now works without overrides) |
| ctkd/ctvd | none | q8_0 (draft KV cache quantization) |
| -ctxcp | none | 64 (context checkpoints) |
| context | 120000 | 65536 (65K sweet spot on 16GB VRAM per njannasch) |
| batch/ubatch | default | 2048/2048 (coder543 ubatch trick) |

### Benchmark results: +43% improvement

| Task | Baseline tok/s | Optimized tok/s | Change |
|------|---------------|-----------------|--------|
| lru_cache | 19.23 | 24.22 | +26% |
| topological_sort | 19.77 | 30.01 | +52% |
| word_break_paths | 17.28 | 26.3 | +53% |
| **Average** | **18.76** | **26.84** | **+43%** |

### Critical lesson: --fit conflicts with manual overrides

In llama.cpp b9360, `--fit` defaults to ON. Setting `-ngl` or `--n-cpu-moe` creates
tensor_buft_overrides that conflict with fit, causing "n_gpu_layers already set" or
"tensor_buft_overrides already set" errors → server crash → system destabilized.

**Fix**: Remove `-ngl` and `--n-cpu-moe` entirely, let fit handle the GPU/CPU/MoE split.
This is the approach used by the Reddit 110tok/s guide and 8GB VRAM config posts.

## Important files

- `start-server-q4ks-mtp.ps1` (Unsloth UD-Q4_K_S + MTP, best Q4 config)
- `start-server-q4ks-vanilla.ps1` (UD-Q4_K_S baseline, no MTP)
- `start-server-vanilla.ps1` (Q4_K_M baseline, proven 36.1 tok/s)
- `start-server-optimized.ps1` (Q4_K_M MTP config, Reddit proven)
- `start-server-moe-offload.ps1` (explicit MoE CPU split, 23.1 tok/s — worse than --fit auto)
- `start-server.ps1` (original, has fit/override conflict bug)
- `start-server-bg-optimized.ps1` (background launcher for optimized)
- `start-server-bg.ps1` (background launcher, original)
- `stop-server.ps1`
- `benchmark_qwen_mtp.py`
- `micro_matrix.py`

## Hardware constraints

- **GPU**: RTX 5060 Ti 16GB (448 GB/s VRAM bandwidth)
- **CPU**: Intel i5-14600KF, 20 threads, DDR4-2400/2667 RAM (~38 GB/s)
- **Windows**: slower than Linux for llama.cpp (no --mlock, --prio/--poll crash)
- **DDR4 vs DDR5**: Our DDR4 bandwidth is 2.5x slower than DDR5-6000 (~96 GB/s)
- This means CPU MoE offload is bandwidth-starved on our system

## Benchmark comparison (2026-06-06)

| Config | Quant | Size | Benchmark avg | Notes |
|--------|-------|------|-------------|-------|
| **UD-Q4_K_S MTP** | Unsloth Q4_K_S | 19.9GB | **33.95 tok/s** | **Best Q4 config! MTP +2.9% boost** |
| **UD-Q4_K_S vanilla** | Unsloth Q4_K_S | 19.9GB | **33.0 tok/s** | Baseline for Q4_K_S |
| havenoammo Q4_K_XL vanilla | havenoammo Q4_K_XL | 21.7GB | 36.1* tok/s | Single test, different methodology |
| havenoammo Q4_K_XL MTP | havenoammo Q4_K_XL | 21.7GB | 26.84 tok/s | MTP hurt (-26%) on DDR4 |
| MoE explicit offload | havenoammo Q4_K_XL | 21.7GB | 23.1 tok/s | DDR4 can't handle all experts on CPU |
| User's Q3.5 | Q3.5 Q4_K_M | ~22GB | 45 tok/s | Q3.5 has no nextn heads (1.5GB less) |

(*Note: 36.1 was a single long-prompt test, not the benchmark script.)

### Per-task MTP comparison (UD-Q4_K_S)

| Task | Vanilla | MTP | MTP Boost |
|------|---------|-----|-----------|
| lru_cache | 37.39 tok/s | 40.77 tok/s | **+9%** |
| topological_sort | 31.82 tok/s | 32.13 tok/s | +1% |
| word_break_paths | 29.80 tok/s | 28.94 tok/s | -3% |
| **Average** | **33.0 tok/s** | **33.95 tok/s** | **+2.9%** |

MTP acceptance rate: 96-100% (near perfect). MTP helps most for coding patterns (lru_cache).
Shorter tasks don't benefit much because MTP overhead proportionally larger.

### Why UD-Q4_K_S works better than Q4_K_XL for MTP on DDR4

1. 1.8GB smaller file → less CPU offload → DDR4 bandwidth pressure reduced
2. MTP context overhead: 565 MiB (Q4_K_S) vs 2056 MiB (Q4_K_XL) → 3.6x less draft overhead
3. More VRAM headroom means fit can keep more model on GPU, less on CPU
4. Result: MTP goes from -26% penalty to +2.9% boost

**Key finding**: --fit auto (36.1 tok/s) is better than explicit MoE offload (23.1 tok/s) on DDR4.
--fit finds a better GPU/CPU split than "all experts on CPU".

**MTP hurts on DDR4**: adds ~2.8GB draft overhead → more CPU offload → DDR4 bottleneck worsens.
On systems where model fits entirely in VRAM (IQ3_S ~14.3GB), MTP boosts 98→144 tok/s (njannasch.dev).

## Q3.6 vs Q3.5 speed gap explanation

User gets 45 tok/s on Q3.5 but 36 tok/s on Q3.6 baseline (same hardware, similar model size).
The ~9 tok/s gap is because:
1. Q3.6 MTP GGUF includes ~1.5GB nextn prediction heads (even without MTP enabled)
2. More data → more CPU offload → more DDR4 bandwidth pressure
3. Non-MTP Q3.6 GGUF would be ~1.5GB smaller (see unsloth non-MTP repo)

## Critical finding: prompt cache kills DDR4 performance (2026-06-06)

The llama.cpp prompt cache (`--cache-ram`, default 8192 MiB) accumulates past prompts in VRAM.
On DDR4 systems, this VRAM consumption forces --fit to offload more model weights to DDR4 → speed collapse.

| Model | Prompt cache | Avg tok/s | Task 2-3 avg |
|-------|-------------|-----------|-------------|
| 27B IQ3_XXS + q4_0 KV | ON (default) | 16.69 | 18.6→13.6 (declining!) |
| 27B IQ3_XXS + q4_0 KV | OFF (--cache-ram 0) | 22.47 | **26.14** (stable) |

With prompt cache ON, speed drops 18.6→13.6 tok/s across tasks as cache accumulates.
With prompt cache OFF, speed is stable at ~26 tok/s across tasks 2-3.

**Fix**: Add `--cache-ram 0` to disable prompt cache on DDR4 systems where VRAM is tight.

## KV cache research: q4_0 is lossless on Qwen hybrid models

Per llama.cpp issue #21385: `-ctk q4_0 -ctv q4_0` produces **BLEU 1.000** (token-identical)
on Qwen3.5 hybrid models at 4x compression vs f16. Why: Qwen uses only 8/32 layers for full
attention (KV cache). The other 24 layers use Gated Delta Net (linear attention, no KV cache).
Linear layers absorb quantization noise → lossless result.

For **35B-A3B MoE** (also hybrid): q4_0 KV saves VRAM but is slightly slower than q8_0
because the hybrid KV cache is already tiny — savings don't help, dequant overhead hurts.
Result: q8_0 (33.0) > q4_0 (31.84) for 35B-A3B.

For **27B dense** (all layers have KV cache): q4_0 KV frees ~2-3 GB VRAM → less DDR4 offload.
Critical for fitting IQ4_XS. But IQ4_XS still too big — IQ3_XXS needed.

## 27B dense benchmark results (2026-06-06)

| Model | Quant | KV cache | Prompt cache | Avg tok/s | Sustained |
|-------|-------|----------|-------------|-----------|-----------|
| 27B IQ4_XS | 14.38GB | q8_0 | ON | 5.96 | Terrible (model+KV > VRAM) |
| 27B IQ4_XS | 14.38GB | q4_0 | ON | 8.68 | Still terrible |
| 27B IQ3_XXS | 11.17GB | q4_0 | ON | 16.69 | Declining (cache eats VRAM) |
| **27B IQ3_XXS** | **11.17GB** | **q4_0** | **OFF** | **22.47** | **~26 stable** |

IQ4_XS (14.38GB) doesn't work on 16GB VRAM regardless of KV cache type.
IQ3_XXS (11.17GB) works with q4_0 KV + prompt cache disabled = ~26 tok/s sustained.

### 35B-A3B KV cache comparison

| KV cache | Avg tok/s | Notes |
|----------|-----------|-------|
| q8_0 | 33.0 | **Best for 35B-A3B MoE** |
| q4_0 | 31.84 | Slightly slower (hybrid KV already tiny) |

## Q3.6-27B dense model analysis

### Why consider 27B dense alongside 35B-A3B MoE?

- njannasch: "dense model scores higher on coding benchmarks but runs at 31 t/s vs 98 t/s for MoE"
- 27B dense = better code quality, but slower than 35B-A3B MoE
- MTP **hurts** dense models: njannasch shows -42% (31→16.4 tok/s with IQ3_XXS)
- Use **non-MTP** GGUF for 27B — MTP overhead small (~0.25 GB) but performance penalty huge

### 27B dense GGUF sizes (non-MTP repo: `unsloth/Qwen3.6-27B-GGUF`)

| Quant | Size | Fits 16GB? | Expected speed (Win) | Quality |
|-------|------|-----------|---------------------|---------|
| UD-IQ3_XXS | 11.17 GB | YES (entirely) | ~26-28 tok/s | Lowest |
| Q3_K_M | 12.65 GB | YES (entirely) | ~26-28 tok/s | Low |
| IQ4_XS | 14.38 GB | YES (tight KV) | ~25-27 tok/s | Medium |
| Q4_K_S | 14.77 GB | Borderline | ~24-26 tok/s | Good |
| IQ4_NL | 14.97 GB | Borderline | ~24-26 tok/s | Good |
| Q4_K_M | 15.66 GB | Needs offload | ~22-24 tok/s | Best viable Q4 |
| UD-Q4_K_XL | 16.40 GB | Needs offload | ~20-22 tok/s | Best Q4 |

Speed estimates: njannasch Linux baseline 31 tok/s (IQ3_XXS), Windows ~10-15% penalty.
Dense model reads ALL 27B params per token (no MoE sparsity savings) → bandwidth heavy.

### Recommended 27B dense config

**Best balance**: **Q4_K_S non-MTP (14.77 GB)** — good quality, fits mostly in VRAM with --fit auto
**Safe fit**: **IQ4_XS non-MTP (14.38 GB)** — guaranteed full VRAM fit, slightly lower quality
**Budget**: **UD-IQ3_XXS non-MTP (11.17 GB)** — fastest, lowest quality

### 27B vs 35B-A3B comparison for this hardware

| Model | Quant | Speed | Code quality | Trade-off |
|-------|-------|-------|-------------|-----------|
| 35B-A3B MoE | UD-Q4_K_S | ~33-34 tok/s | Good (3.6B active) | Fast but MoE quality |
| 27B dense | Q4_K_S | ~24-26 tok/s | Better (all 27B active) | Slower but denser quality |
| 35B-A3B MoE | UD-IQ3_S | ~98+ tok/s (if fits VRAM) | Good | Very fast but low quant |

### MoE vs Dense bandwidth explanation

- 35B-A3B MoE: activates 3.6B/35B per token → ~10% of model bandwidth used → GPU has headroom
- 27B dense: activates ALL 27B per token → ~76% of bandwidth used → GPU saturated
- This is why MTP works on MoE (headroom exists) but hurts dense (no headroom, draft steals bandwidth)

## Available Q4 quants (Unsloth)

| File | Size | MTP? | Fits 16GB? |
|------|------|------|-----------|
| UD-Q4_K_S MTP | 19.9 GB | Yes | No (less offload) |
| UD-Q4_K_M MTP | 21.1 GB | Yes | No |
| UD-Q4_K_XL MTP (Unsloth) | 21.3 GB | Yes | No |
| UD-Q4_K_XL MTP (havenoammo) | 21.7 GB | Yes | No (our current) |
| UD-Q4_K_S non-MTP | 19.5 GB | No | No (best Q4 fit) |
| UD-Q4_K_M non-MTP | 20.6 GB | No | No |
| UD-IQ3_S MTP | 14.3 GB | Yes | **YES — fits in VRAM!** |
| UD-IQ3_S non-MTP | 12.7 GB | No | YES |

Downloading UD-Q4_K_S MTP (19.9GB) — 1.8GB smaller = less CPU offload = faster baseline.

## Reference benchmarks (other hardware)

| Source | GPU | Quant | Speed | Key |
|--------|-----|-------|-------|-----|
| njannasch.dev | RTX 5060 Ti 16GB (Linux) | IQ3_S | 144 tok/s MTP / 98 baseline | Fits entirely in VRAM (-ngl 99) |
| carteakey.dev | RTX 4070 12GB | Q4_K_XL | 67 tok/s MTP / 51 baseline | --fit 1536, DDR5-6000 |
| Reddit 80tok/s | RTX 4070 Super 12GB | Q4_K_XL | 80 tok/s MTP | -fitt 1536, Linux, DDR5-6000 |
| aminrj.com | RTX 3090 24GB | Q4_K_M | 101.7 tok/s Q3.6 baseline | Fits entirely in VRAM
