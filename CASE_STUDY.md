## Case Study: Qwen3.6 on RTX 5060 Ti 16GB + DDR4 + Windows

### TL;DR

On DDR4 bandwidth-starved hardware, a smaller dense model (27B IQ3_XXS at ~26 tok/s) produces **better code** than a bigger MoE model (35B-A3B Q4_K_S at ~33 tok/s). Speed is misleading — quality per token matters more.

---

### Hardware

| Component | Spec | Constraint |
|-----------|------|------------|
| GPU | RTX 5060 Ti 16GB | 448 GB/s VRAM bandwidth, 16GB VRAM |
| CPU | Intel i5-14600KF | 20 threads, DDR4-2400/2667 RAM |
| RAM bandwidth | ~38 GB/s | **2.5x slower** than DDR5-6000 (~96 GB/s) |
| OS | Windows 11 | No --mlock, --prio/--poll crash; ~10-15% slower than Linux |

**Key bottleneck**: DDR4 bandwidth at 38 GB/s. Anything offloaded to CPU RAM is bandwidth-starved.

---

### Models tested

| Model | Quant | Size | KV cache | Prompt cache | Speed | Coding quality |
|-------|-------|------|----------|-------------|-------|---------------|
| **27B dense IQ3_XXS** | UD-IQ3_XXS | 11.17GB | q4_0 | OFF (--cache-ram 0) | **~26 tok/s stable** | **Best — passed all tests** |
| 35B-A3B MoE Q4_K_S | UD-Q4_K_S | 19.9GB | q8_0 | OFF (--cache-ram 0) | ~33 tok/s | Failed multi-step reasoning |
| 35B-A3B MoE Q4_K_S MTP | UD-Q4_K_S | 19.9GB | q8_0 | OFF | ~34 tok/s (+2.9%) | Same quality, tiny speed gain |
| 27B dense IQ4_XS | IQ4_XS | 14.38GB | q4_0 | ON | 5.96-8.68 tok/s | Unusable (too big for 16GB) |
| 27B dense IQ4_XS | IQ4_XS | 14.38GB | q8_0 | ON | 5.96 tok/s | Unusable |
| 27B dense IQ3_XXS | UD-IQ3_XXS | 11.17GB | q4_0 | ON (default) | 16.69 declining | Good but speed collapses |
| havenoammo Q4_K_XL MTP | Q4_K_XL | 21.7GB | q8_0 | ON | 26.84 tok/s | MTP hurts DDR4 (-26%) |
| MoE explicit offload | Q4_K_XL | 21.7GB | — | ON | 23.1 tok/s | Worse than --fit auto |

---

### Coding quality comparison (real tests)

**Sudoku solver** (backtracking + constraint propagation):
- 27B IQ3_XXS: Correct solution, row 0 = [5,3,4] verified
- 35B-A3B Q4_K_S: Correct solution (with thinking enabled)

**Multi-step bank simulation** (8 dependent steps with conditionals):
- 27B IQ3_XXS: **Correct** — (334.75, 523.24, 238.14)
- 35B-A3B Q4_K_S: **Wrong** — (190.55, 523.24, 6.39)
  - Failed step 4: subtracted entire transfer from both A and B instead of halving each
  - Used 13,516 tokens (mostly wrong reasoning) vs 27B's concise correct answer

**Winner**: 27B dense IQ3_XXS — better reasoning despite lower quant and slower speed.

---

### Key lessons learned

#### 1. DDR4 bandwidth is the real bottleneck

Models >16GB must offload to CPU RAM. DDR4 at ~38 GB/s is 2.5x slower than DDR5-6000.
Every GB offloaded steals bandwidth from generation. Result:
- IQ4_XS (14.38GB) barely fits but KV cache pushes it over → catastrophic speed
- IQ3_XXS (11.17GB) fits with room → stable ~26 tok/s

**Lesson**: On DDR4, model size matters more than quant quality. Fit in VRAM first.

#### 2. Prompt cache kills DDR4 performance

llama.cpp defaults `--cache-ram 8192 MiB`. This accumulates past prompts in VRAM,
forcing --fit to offload more weights to DDR4. Speed progressively degrades:

| Prompt cache | 27B IQ3_XXS avg | Sustained (tasks 2-3) |
|-------------|----------------|-----------------------|
| ON (default) | 16.69 tok/s | 18.6→13.6 (declining!) |
| OFF (--cache-ram 0) | 22.47 tok/s | ~26 stable |

**Lesson**: Always use `--cache-ram 0` on DDR4-constrained systems. Prompt cache is
only useful when VRAM is abundant.

#### 3. KV cache: q4_0 is lossless but not always faster

Per llama.cpp #21385: q4_0 KV produces BLEU 1.000 on Qwen hybrid models (only 8/32
layers use full attention). But:
- For 35B-A3B MoE (hybrid, tiny KV): q8_0 (33.0) > q4_0 (31.84) — savings too small, dequant overhead hurts
- For 27B dense (all layers have KV): q4_0 frees ~2-3GB VRAM → less DDR4 offload → faster overall

**Lesson**: q4_0 KV for dense models (frees real VRAM), q8_0 KV for hybrid MoE (hybrid KV already tiny).

#### 4. --fit auto beats manual MoE offload on DDR4

| Approach | Speed |
|----------|-------|
| --fit auto | 36.1 tok/s (baseline) |
| Explicit MoE offload (all experts on CPU) | 23.1 tok/s |

Manual overrides (-ngl, --n-cpu-moe) also conflict with --fit and can crash the server.

**Lesson**: Remove -ngl and --n-cpu-moe entirely. Let --fit find the optimal GPU/CPU split.

#### 5. MTP: +2.9% on MoE, -42% on dense, -26% on large MoE+DDR4

| Model | MTP effect | Reason |
|-------|-----------|--------|
| 35B-A3B UD-Q4_K_S (19.9GB) | +2.9% | Small model = less DDR4 pressure, MTP headroom exists |
| havenoammo Q4_K_XL (21.7GB) | -26% | Large model = heavy DDR4 offload, MTP adds 2.8GB overhead |
| 27B dense IQ3_XXS | -42% (njannasch) | No GPU headroom, draft steals bandwidth from dense reads |
| IQ3_S (fits entirely in VRAM) | +47% (98→144, njannasch) | No DDR4 bottleneck, pure speed boost |

**Lesson**: MTP only helps when model fits entirely in VRAM OR when DDR4 overhead is minimal.
On DDR4-constrained systems, MTP is net negative for most configs.

#### 6. Dense > MoE for coding quality on bandwidth-starved hardware

MoE activates only 3.6B/35B per token (10% of parameters). Dense activates ALL 27B (76%).
Even at IQ3_XXS quant, the dense model has more active reasoning capacity per token:

| Metric | 27B dense IQ3_XXS | 35B-A3B MoE Q4_K_S |
|--------|--------------------|---------------------|
| Active params per token | 27B (all) | 3.6B (10%) |
| Speed | ~26 tok/s | ~33 tok/s |
| Sudoku | Correct | Correct |
| Bank simulation (8 steps) | Correct | Wrong |
| Tokens used (bank) | Few, correct | 13,516, wrong |

**Lesson**: For coding/reasoning tasks, slower dense model > faster MoE. Speed without
correctness is wasted computation.

#### 7. Thinking mode bug: sends reasoning_content, leaves content empty

Qwen3.6 defaults to thinking mode. Without `enable_thinking: false`, the model:
- Writes long reasoning into `reasoning_content`
- Leaves `content` empty or minimal
- Burns thousands of tokens on reasoning (13,516 in bank test)

**Fix**: Send `chat_template_kwargs.enable_thinking: false` at top level in API requests.
`reasoning: "off"` or `reasoning_budget: 0` do NOT work for this setup.

**Lesson**: Always disable thinking for plain chat/coding requests unless you explicitly
want reasoning output.

#### 8. Only one llama-server at a time

Running two servers simultaneously destabilizes the system. Always kill all existing
processes before starting a new one.

**Fix**: `taskkill //F //IM llama-server.exe` in bash, then start new server.

---

### Recommended configs

#### Best for coding: 27B dense IQ3_XXS (start-server-27b-iq3xxs.ps1)

```
-m Qwen3.6-27B-UD-IQ3_XXS.gguf
--jinja -t 16 -c 65536 -n 32768 -np 1 -fa on
-ctk q4_0 -ctv q4_0
--no-mmap --no-warmup --cache-ram 0
```

- ~26 tok/s sustained, best coding quality, passes hard tests
- No MTP (MTP hurts dense -42%)

#### Fastest for casual use: 35B-A3B MoE Q4_K_S (start-server-q4ks-vanilla.ps1)

```
-m Qwen3.6-35B-A3B-UD-Q4_K_S.gguf
--jinja -t 16 -c 65536 -n 32768 -np 1 -fa on
-ctk q8_0 -ctv q8_0
--no-mmap --cache-ram 0
```

- ~33 tok/s, good for simple tasks, weaker on multi-step reasoning

#### Opencode integration

Both models configured in `~/.config/opencode/opencode.json` as `local` provider:
- `local/qwen3.6-27b-iq3xxs` — best for coding
- `local/qwen3.6-35b-q4ks` — fastest for casual use
- Both point to `http://127.0.0.1:8080/v1` (OpenAI-compatible via @ai-sdk/openai-compatible)
- Switch with `/models` in opencode; start matching llama-server first

---

### What didn't work

| Attempt | Why it failed |
|---------|---------------|
| IQ4_XS 27B (14.38GB) | Model + KV > 16GB VRAM → DDR4 offload → 5-8 tok/s |
| IQ4_XS + q4_0 KV | Still too big, only 8.68 tok/s |
| IQ3_XXS + default prompt cache | Speed degrades 18.6→13.6 as cache accumulates |
| q4_0 KV on 35B-A3B MoE | Slower than q8_0 (hybrid KV already tiny) |
| MTP on DDR4-constrained configs | Net negative or marginal (+2.9%) |
| Manual MoE offload (-ngl, --n-cpu-moe) | Conflicts with --fit, crashes server |
| reasoning: "off" | Doesn't fix thinking bug for Qwen3.6 |

---

### Reference: other hardware benchmarks

| Source | GPU | RAM | Quant | Speed | Key insight |
|--------|-----|-----|-------|-------|-------------|
| njannasch.dev | RTX 5060 Ti 16GB (Linux) | DDR5 | IQ3_S | 144 MTP / 98 base | Fits entirely in VRAM = MTP shines |
| carteakey.dev | RTX 4070 12GB | DDR5-6000 | Q4_K_XL | 67 MTP / 51 base | DDR5 makes offload tolerable |
| Reddit 80tok/s | RTX 4070 Super 12GB | DDR5-6000 | Q4_K_XL | 80 MTP | DDR5 + Linux = much faster than us |
| aminrj.com | RTX 3090 24GB | — | Q4_K_M | 101.7 base | 24GB VRAM = fits entirely, no DDR4 issue |

**Pattern**: All fast results use DDR5 or 24GB+ VRAM. Our DDR4 is the bottleneck everywhere.

---

### Bottom line

On DDR4-constrained hardware (16GB VRAM, ~38 GB/s RAM bandwidth):
1. **Model fit > quant quality** — IQ3_XXS (11.17GB) beats IQ4_XS (14.38GB) because it fits
2. **Dense > MoE for reasoning** — 27B active params beat 3.6B active params
3. **Prompt cache OFF** — `--cache-ram 0` prevents progressive speed collapse
4. **MTP = net negative** — adds overhead, DDR4 can't absorb it
5. **--fit auto** — beats manual GPU/CPU splits, avoids crash bugs
6. **Disable thinking** — `enable_thinking: false` required for clean chat responses

The 27B IQ3_XXS at ~26 tok/s is the **best coding model** for this hardware. Not the fastest, but the most reliable and accurate.