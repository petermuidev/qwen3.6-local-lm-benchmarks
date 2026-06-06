# Qwen3.6 Local LLM Benchmarks

Benchmarks, configurations, and case study for running Qwen3.6 models locally on **RTX 5060 Ti 16GB + DDR4 RAM + Windows 11**.

## Key Finding

On DDR4 bandwidth-starved hardware (~38 GB/s), a smaller **dense model** (27B IQ3_XXS at ~26 tok/s) produces **better code** than a bigger **MoE model** (35B-A3B Q4_K_S at ~33 tok/s). Speed is misleading — the dense model activates all 27B parameters per token vs MoE's 3.6B/35B, giving more reasoning capacity per step.

| Model | Speed | Sudoku | Bank simulation (8 steps) | Tokens used |
|-------|-------|--------|--------------------------|-------------|
| 27B dense IQ3_XXS | ~26 tok/s | Correct | **Correct** (334.75, 523.24, 238.14) | Few |
| 35B-A3B MoE Q4_K_S | ~33 tok/s | Correct | **Wrong** (190.55, 523.24, 6.39) | 13,516 |

## Quick Start

### Best for coding — 27B dense IQ3_XXS (~26 tok/s)

```powershell
.\start-server-27b-iq3xxs.ps1
```

Model: Unsloth UD-IQ3_XXS (11.17GB), KV: q4_0, prompt cache OFF, no MTP.

### Fastest for casual use — 35B-A3B MoE Q4_K_S (~33 tok/s)

```powershell
.\start-server-q4ks-vanilla.ps1
```

Model: Unsloth UD-Q4_K_S (19.9GB), KV: q8_0, prompt cache OFF, no MTP.

### Stop server

```powershell
.\stop-server.ps1
```

## Models Required

Download from Unsloth GGUF repos:

| Model | Repo | File | Size |
|-------|------|------|------|
| 27B IQ3_XXS | `unsloth/Qwen3.6-27B-GGUF` | `Qwen3.6-27B-UD-IQ3_XXS.gguf` | 11.17 GB |
| 35B-A3B Q4_K_S | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` | `Qwen3.6-35B-A3B-UD-Q4_K_S.gguf` | 19.9 GB |

Place files in `models/Qwen3.6-27B-GGUF/` and `models/Qwen3.6-35B-A3B-MTP-GGUF/`.

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

## 8 Key Lessons

1. **DDR4 bandwidth is the bottleneck** — Model fit > quant quality. IQ3_XXS (11.17GB) beats IQ4_XS (14.38GB) because it fits in VRAM.
2. **Prompt cache kills DDR4 performance** — `--cache-ram 0` prevents progressive speed collapse (18.6→13.6 tok/s → stable ~26 tok/s).
3. **q4_0 KV is lossless but not always faster** — Best for dense (frees real VRAM), worse for hybrid MoE (tiny KV already, dequant overhead hurts).
4. **`--fit` auto beats manual MoE offload** — 36.1 tok/s vs 23.1 tok/s. Manual `-ngl`/`--n-cpu-moe` conflicts with `--fit` and crashes.
5. **MTP is net negative on DDR4** — +2.9% on small MoE, -26% on large MoE, -42% on dense. Only helps when model fits entirely in VRAM.
6. **Dense > MoE for coding on DDR4** — All 27B params active vs 3.6B/35B = better reasoning quality.
7. **Disable thinking** — Send `chat_template_kwargs.enable_thinking: false` to avoid empty `content` responses.
8. **Only one llama-server at a time** — Multiple servers destabilize the system.

## Hardware

| Component | Spec |
|-----------|------|
| GPU | RTX 5060 Ti 16GB (448 GB/s) |
| CPU | Intel i5-14600KF (20 threads) |
| RAM | DDR4-2400/2667 (~38 GB/s) |
| OS | Windows 11 Pro |

## Full Details

- [CASE_STUDY.md](CASE_STUDY.md) — Complete case study with all benchmarks, tests, and analysis
- [SUMMARY.md](SUMMARY.md) — Technical summary with configuration history and research notes

## License

Configs and documentation — use freely. Model files subject to Unsloth/Qwen license terms.