# Qwen3.6 Local LLM Benchmarks

Benchmarks, configurations, and case study for running Qwen3.6 models locally on **RTX 5060 Ti 16GB + DDR4 RAM + Windows 11**.

## Key Finding

On DDR4 bandwidth-starved hardware (~38 GB/s), a smaller **dense model** (27B IQ3_XXS at ~26 tok/s) produces **better code** than a bigger **MoE model** (35B-A3B Q4_K_S at ~33 tok/s). Speed is misleading — the dense model activates all 27B parameters per token vs MoE's 3.6B/35B, giving more reasoning capacity per step.

**NEW**: Switching to ik_llama.cpp with `--n-cpu-moe 16` takes the same MoE config from ~26 tok/s to **61 tok/s** on identical hardware (proven by bobaburger on r/LocalLLaMA). This changes the MoE vs dense calculus — see [CONFIG_GUIDE.md](CONFIG_GUIDE.md).

| Model | Speed | Sudoku | Bank simulation (8 steps) | Tokens used |
|-------|-------|--------|--------------------------|-------------|
| 27B dense IQ3_XXS (upstream) | ~26 tok/s | Correct | **Correct** (334.75, 523.24, 238.14) | Few |
| 35B-A3B MoE Q4_K_S (upstream) | ~33 tok/s | Correct | **Wrong** (190.55, 523.24, 6.39) | 13,516 |
| 35B-A3B MoE Q4_K_M (ik_llama.cpp) | **~61 tok/s** | ? | ? | ? |

## Quick Start

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

### NEW: ik_llama.cpp configs (requires building from source)

These configs use ik_llama.cpp which gives **2-3x speed improvement** on MoE models. Build instructions in [CONFIG_GUIDE.md](CONFIG_GUIDE.md).

| Script | Expected speed | Key flags |
|--------|---------------|-----------|
| `start-server-ik-35b-moe-ncpumoe16.ps1` | ~61 tok/s | `--n-cpu-moe 16 -fmoe` |
| `start-server-ik-35b-moe-fit.ps1` | ~74 tok/s | `--fit -fmoe` (no batch flags) |
| `start-server-ik-27b-mtp.ps1` | ~30-35 tok/s (experimental) | `--spec-type mtp:n_max=1,p_min=0.0` |

### NEW: TurboQuant config (alternative fork)

```powershell
.\start-server-tq-35b-moe-nextn.ps1
```

Different runtime fork (atomic-llama-cpp-turboquant) with TurboQuant KV + NextN speculative decoding. +28-36% on 35B MoE.

### Stop server

```powershell
.\stop-server.ps1
```

## Models Required

### Upstream llama.cpp models (Unsloth)

| Model | Repo | File | Size |
|-------|------|------|------|
| 27B IQ3_XXS | `unsloth/Qwen3.6-27B-GGUF` | `Qwen3.6-27B-UD-IQ3_XXS.gguf` | 11.17 GB |
| 35B-A3B Q4_K_S | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` | `Qwen3.6-35B-A3B-UD-Q4_K_S.gguf` | 19.9 GB |
| 35B-A3B Q4_K_M | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` | `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` | 21.1 GB |

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

## Key Lessons (updated with ik_llama.cpp findings)

1. **ik_llama.cpp is the biggest single fix** — 26→61 tok/s on same hardware with `--n-cpu-moe 16 -fmoe`. See [CONFIG_GUIDE.md](CONFIG_GUIDE.md) for build instructions.
2. **DDR4 bandwidth is the bottleneck** — Model fit > quant quality. IQ3_XXS (11.17GB) beats IQ4_XS (14.38GB) because it fits in VRAM.
3. **Prompt cache kills DDR4 performance** — `--cache-ram 0` prevents progressive speed collapse.
4. **q4_0 KV is lossless but not always faster** — Best for dense (frees VRAM), worse for hybrid MoE.
5. **`--fit` auto beats manual MoE offload on upstream** — 36.1 vs 23.1 tok/s. But ik_llama.cpp `--n-cpu-moe 16` beats both at 61 tok/s.
6. **MTP is net negative on upstream/DDR4** — But ik_llama.cpp MTP for 27B dense (+27% on RTX 3090) changes this; needs testing on DDR4.
7. **Dense > MoE for coding on upstream** — All 27B params active vs 3.6B/35B. With ik_llama.cpp MoE speed gains, re-benchmark quality.
8. **Disable thinking** — Send `chat_template_kwargs.enable_thinking: false`.
9. **Only one llama-server at a time** — Multiple servers destabilize the system.
10. **Do NOT use `-rtr` with `--n-cpu-moe`** — Breaks hybrid CPU/GPU MoE offload in ik_llama.cpp.
11. **Do NOT use Unsloth `_XL` GGUF with ik_llama.cpp** — f16 tensors break it.

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