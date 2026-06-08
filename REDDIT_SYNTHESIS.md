# Qwen 3.6 Reddit Research Synthesis

Evidence-based analysis from 22 Reddit threads in r/LocalLLaMA, fetched June 8 2026.
All claims traced to specific posts with scores and authors.

---

## Table of Contents

1. [Runtime Comparison: llama.cpp vs ik_llama.cpp vs TurboQuant](#runtime-comparison)
2. [Speed Benchmarks by Hardware](#speed-benchmarks)
3. [MTP (Multi-Token Prediction) Findings](#mtp-findings)
4. [Quantization Recommendations](#quantization-recommendations)
5. [RTX 5060 Ti 16GB Specifics](#rtx-5060-ti-16gb)
6. [Windows Performance Warning](#windows-warning)
7. [Validated CONFIG_GUIDE Claims](#validated-claims)
8. [Unverified / Corrected Claims](#unverified-claims)
9. [Key Insights for Our Setup](#key-insights)
10. [Evidence Sources](#evidence-sources)

---

## Runtime Comparison

| Runtime | Stars | MTP Support | MoE Offload | Best For | Source |
|---------|-------|-------------|-------------|----------|--------|
| llama.cpp (upstream) | — | Yes (merged) | `--fit` only, `--cpu-moe` crashes with `--fit` | Baseline, easy setup | Multiple posts |
| ik_llama.cpp | 2704 | Yes (PR #1698 merged) | `--n-cpu-moe N`, `-fmoe`, `--cpu-moe`, `--fit` | Best speed on Linux | [110 tok/s post](https://reddit.com/r/LocalLLaMA/comments/1tjh7az/) |
| atomic-llama-cpp-turboquant | 252 | Yes (NextN) | Standard | TurboQuant KV + weight compression | [TurboQuant post](https://reddit.com/r/LocalLLaMA/comments/1tckzy2/) |

**ik_llama.cpp key advantages over upstream llama.cpp:**
- Higher MTP acceptance rate (0.79-0.97 vs 0.48-0.94) — [janvitos, 386pts](https://reddit.com/r/LocalLLaMA/comments/1tjh7az/)
- `--n-cpu-moe N` flag works correctly (upstream crashes with `--fit`) — [multiple sources](https://reddit.com/r/LocalLLaMA/comments/1so8253/)
- `-fmoe` fused MoE ops — not available upstream
- Custom KS/KSS quants (IQ4_KS = smaller + same quality as IQ4_XL) — [Pablo_the_brave, 81pts](https://reddit.com/r/LocalLLaMA/comments/1tkmgwj/)

**Critical limitation: ik_llama.cpp is NVIDIA CUDA + CPU only** — no AMD or Apple Silicon support.

---

## Speed Benchmarks

### 35B MoE (Qwen3.6-35B-A3B)

| GPU | RAM | Runtime | Quant | Config | Speed | Context | Source |
|-----|-----|---------|-------|--------|-------|---------|--------|
| RTX 4070 Super 12GB | DDR5 | ik_llama.cpp | IQ4_XS 4.19bpw | MTP draft-max=3 | **110 tok/s** avg | 131K | [janvitos, 386pts](https://reddit.com/r/LocalLLaMA/comments/1tjh7az/) |
| RTX 4070 Super 12GB | DDR5 | llama.cpp | IQ4_XS 4.19bpw | MTP draft-max=3 | **89.8 tok/s** avg | 131K | same post |
| RTX 4070 Super 12GB | DDR5 | llama.cpp | IQ4_XS | MTP, 128K ctx | **80 tok/s** | 128K | [janvitos, 675pts](https://reddit.com/r/LocalLLaMA/comments/1t82zxv/) |
| Mac M5 Max 64GB | Unified | TurboQuant | TQ4_1S | MTP + turbo3 KV | **34 tok/s** | — | [gladkos, 385pts](https://reddit.com/r/LocalLLaMA/comments/1tckzy2/) |
| Mac M5 Max 64GB | Unified | TurboQuant | TQ4_1S | No MTP | **21 tok/s** | — | same post |
| Dual RTX 5060 Ti 32GB | 64GB DDR5 | llama.cpp | Q4_K_S | --cpu-moe | **21.7 tok/s** | 90K | [Defilan, 24pts](https://reddit.com/r/LocalLLaMA/comments/1so8253/) |
| RTX 3080 10GB | 32GB DDR5 | llama.cpp | — | -ctk q8_0 -ctv q8_0 | **26 tok/s** tg, 1400 pp | — | [AndreVallestero, 15pts](https://reddit.com/r/LocalLLaMA/comments/1tx9ef5/) |
| RTX 3080 10GB | 32GB DDR5 | llama.cpp | — | + optimize flags | **48.4 tok/s** tg | 32K | u/Diaghilev in same thread |
| Various 6GB VRAM | — | llama.cpp | — | — | **20-34 tok/s** | — | [Low-Alarm272, 294pts](https://reddit.com/r/unsloth/comments/1t5n672/) |

### 27B Dense (Qwen3.6-27B)

| GPU | RAM | Runtime | Quant | Config | Speed | Context | Source |
|-----|-----|---------|-------|--------|-------|---------|--------|
| RTX 3090 24GB | — | ik_llama.cpp | IQ4_KS + MTP | draft-max=4, q8 KV | **72.9 tok/s** tg, 1261 pp | 156K | [VolandBerlioz, 221pts](https://reddit.com/r/LocalLLaMA/comments/1tgis7s/) |
| Mac M2 Max 96GB | Unified | llama.cpp | — | MTP | **28 tok/s** | — | [ex-arman68, 1233pts](https://reddit.com/r/LocalLLaMA/comments/1t57xuu/) |
| RTX 3090 | — | llama.cpp | — | MTP | **50 tok/s** | 100K | u/admajic in same thread |
| 16GB VRAM NVIDIA | — | ik_llama.cpp | IQ4_KS 14.1GB | q4_0 KV, -khad -vhad | **1.5-1.75x faster than IQ4_XS** | 105K | [Pablo_the_brave, 81pts](https://reddit.com/r/LocalLLaMA/comments/1tkmgwj/) |
| — | — | llama.cpp | BF16 | — | **15.5 tok/s** | — | [gvij, 718pts](https://reddit.com/r/LocalLLaMA/comments/1sxzqry/) |
| — | — | llama.cpp | Q4_K_M | — | **22.5 tok/s** | — | same post |
| — | — | llama.cpp | Q8_0 | — | **18.0 tok/s** | — | same post |

### Our Current Setup (RTX 5060 Ti 16GB + DDR4)

| Model | Runtime | Quant | Config | Speed | Score | Source |
|-------|---------|-------|--------|-------|-------|--------|
| 27B dense | llama.cpp b9360 | IQ3_XXS 11.17GB | q4_0 KV, no MTP | **~26 tok/s** | Correct on bank sim | Our benchmarks |
| 35B MoE | llama.cpp b9360 | Q4_K_S 19.9GB | q8_0 KV, --fit | **~33 tok/s** | Wrong on bank sim | Our benchmarks |

---

## MTP Findings

**What is MTP?** Multi-Token Prediction — the model predicts multiple tokens per forward pass, then accepts/rejects them. Higher acceptance rate = faster generation.

### MTP Acceptance Rates

| Runtime | Min Accept | Max Accept | Avg Accept | Source |
|---------|-----------|-----------|-----------|--------|
| ik_llama.cpp | 0.790 | 0.967 | ~0.91 | [janvitos, 386pts](https://reddit.com/r/LocalLLaMA/comments/1tjh7az/) |
| llama.cpp (after MTP PR merge) | 0.477 | 0.967 | ~0.80 | same post (before switch) |
| llama.cpp (before PR merge) | — | — | ~0.95 | [janvitos earlier, 675pts](https://reddit.com/r/LocalLLaMA/comments/1t82zxv/) |

**Key finding from janvitos:** llama.cpp MTP performance dropped after the PR was officially merged. ik_llama.cpp MTP acceptance rate is consistently higher.

### MTP Speed Impact

| Setup | Without MTP | With MTP | Speedup | Source |
|-------|------------|----------|---------|--------|
| 35B MoE, RTX 4070S 12GB, ik_llama | ~60 tok/s est. | 110 tok/s | **~1.8x** | [janvitos, 386pts](https://reddit.com/r/LocalLLaMA/comments/1tjh7az/) |
| 27B dense, Mac M2 Max | 11.2 tok/s | 28 tok/s | **2.5x** | [ex-arman68, 1233pts](https://reddit.com/r/LocalLLaMA/comments/1t57xuu/) |
| 35B MoE, Mac M5 Max, TurboQuant | 21 tok/s | 34 tok/s | **1.6x** | [gladkos, 385pts](https://reddit.com/r/LocalLLaMA/comments/1tckzy2/) |
| 35B MoE, 1M tokens test | 21.4 tok/s | 33.4 tok/s | **1.56x** | [Jorlen, 133pts](https://reddit.com/r/LocalLLaMA/comments/1tdns1i/) |
| 27B dense, 2x RTX 3090, ik_llama layer mode | 23.3 tok/s | 29.6 tok/s | **1.27x** | CONFIG_GUIDE (Reddit PR discussion) |

### MTP Best Practices (from evidence)

- **draft-max=1** for 27B dense on ik_llama.cpp (82-87% accept). draft-max=2 gives diminishing returns (51% accept) — CONFIG_GUIDE citing PR #1698
- **draft-max=3-4** works well for 35B MoE with ik_llama.cpp — [janvitos, 386pts](https://reddit.com/r/LocalLLaMA/comments/1tjh7az/)
- **MTP GGUF required** — standard GGUF lacks the MTP prediction head layers
- **MTP hurts prompt processing** by ~20% — u/gordi555 (42pts) in [ex-arman68 thread](https://reddit.com/r/LocalLLaMA/comments/1t57xuu/)

---

## Quantization Recommendations

### For 16GB VRAM (Our Hardware)

| Quant | Size | Fits 16GB? | Quality | Source | Notes |
|-------|------|-----------|---------|--------|-------|
| **IQ4_KS** (27B, ik_llama only) | 14.1GB | Yes (105K ctx) | ≈ IQ4_XL | [Pablo_the_brave, 81pts](https://reddit.com/r/LocalLLaMA/comments/1tkmgwj/) | Best for 16GB VRAM + ik_llama |
| **IQ3_XXS** (27B, Unsloth) | 11.17GB | Yes (comfortable) | Good enough for coding | Our benchmarks | Our current default |
| **IQ4_XS** (27B, Unsloth) | 14.38GB | Tight | Slightly better than IQ3_XXS | Our benchmarks | DDR4 offload hurts |
| **Q4_K_M** (35B MoE) | ~19.9GB | No (needs offload) | Good with ik_llama | [Defilan, 24pts](https://reddit.com/r/LocalLLaMA/comments/1so8253/) | Requires MoE offload |
| **IQ4_XS 4.19bpw** (35B MoE, byteshape) | ~16GB | Barely | ≈ Unsloth Q4_K_XL | [janvitos, 386pts](https://reddit.com/r/LocalLLaMA/comments/1tjh7az/) | 4GB smaller than Q4_K_XL |
| **TQ4_1S** (35B MoE, TurboQuant) | — | — | — | [gladkos, 385pts](https://reddit.com/r/LocalLLaMA/comments/1tckzy2/) | AtomicChat pre-built |

### IQ4_KS — The 16GB Sweet Spot

From [Pablo_the_brave, 81pts](https://reddit.com/r/LocalLLaMA/comments/1tkmgwj/):
- 14.1GB model → fits in 16GB VRAM with room for 105K context
- Requires ik_llama.cpp (KS/KSS quants not in upstream llama.cpp)
- With q4_0 Hadamard KV cache (`-khad -vhad -ctk q4_0 -ctv q4_0`)
- 1.5-1.75x faster than IQ4_XS
- PPL: 7.4040 (comparable to IQ4_XS)
- Eliminates "blank outputs" issue
- Model: [cHunter789/Qwen3.6-27B-i1-IQ4_KS-GGUF](https://huggingface.co/cHunter789/Qwen3.6-27B-i1-IQ4_KS-GGUF)

---

## RTX 5060 Ti 16GB Specifics

### From [Imaginary-Anywhere23, 33pts](https://reddit.com/r/LocalLLaMA/comments/1ryze51/):

The RTX 5060 Ti 16GB findings post uses **upstream llama.cpp b8373**:

| Model | Speed | Notes |
|-------|-------|-------|
| Qwen3-Coder-30B UD-Q3_K_XL | **76.3 tok/s** | Best default coding model |
| Qwen3.5-35B UD-Q2_K_XL | **80.1 tok/s** | Surprisingly fast |
| Qwen3.5 27B Q3_K_S | ~20 tok/s | Slow |
| Qwen3.5 9B Q4_K_M | 64 tok/s | |
| Qwen3.5 4B Q5_K_M | 88 tok/s | |

**Key insight from this post:** On 5060 Ti 16GB, models that fit entirely in VRAM (like Q3_K_XL at ~14GB) are dramatically faster than anything that needs DDR4 offload. The 35B Q4_K_M with offload was "interesting but still not the right default."

**Important:** These speeds are with DDR4 on upstream llama.cpp. ik_llama.cpp would likely improve the offloaded configs significantly.

### From [Defilan, 24pts](https://reddit.com/r/LocalLLaMA/comments/1so8253/) (Dual 5060 Ti 32GB):

Using upstream llama.cpp with `--cpu-moe`:
- Qwen 3.6 35B MoE: 21.7 tok/s at 90K context
- Qwen 3-Coder 30B MoE: 31.1 tok/s (faster despite also being MoE)
- Qwen 3.5 27B dense: 18.3 tok/s (slower generation, faster prefill at 160 tok/s)

**Key insight:** Dense wins prefill (160 tok/s vs 30-95 for MoE), MoE wins generation speed because only active experts travel over PCIe per token.

---

## Windows Warning

### Evidence from Reddit

1. **u/R_Duncan (9pts)** in the [110 tok/s thread](https://reddit.com/r/LocalLLaMA/comments/1tjh7az/):
   > "Too sad this happens only on cachyOS, results of ik_llama in windows were disappointing."

2. **u/FullOf_Bad_Ideas (3pts)** in the [ik_llama Windows builds thread](https://reddit.com/r/LocalLLaMA/comments/1qwo5ig/):
   > "I tried using ik_llama.cpp a few days ago and while it compiled relatively easy, I was getting terrible performance (0.5 t/s TG)"

3. **All verified high-speed benchmarks are on Linux** (CachyOS, Ubuntu):
   - 110 tok/s → CachyOS + RTX 4070 Super + DDR5
   - 72.9 tok/s → Linux + RTX 3090
   - 80 tok/s → CachyOS (earlier janvitos post)

4. **Pre-built Windows binaries exist:**
   - [Thireus fork, 60pts](https://reddit.com/r/LocalLLaMA/comments/1qwo5ig/) — releases for macOS, Ubuntu, Windows
   - [X5R HuggingFace, 38pts](https://reddit.com/r/LocalLLaMA/comments/1mga3ox/) — prebuilt Windows binary
   - [Danmoreng build script, 10pts](https://reddit.com/r/LocalLLaMA/comments/1mga3ox/) — PowerShell all-in-one

5. **No verified Windows speed benchmarks found.** Zero posts with confirmed tok/s numbers on Windows + ik_llama.cpp + Qwen 3.6.

### Assessment

The Windows performance penalty for ik_llama.cpp is **real but unquantified**. It could be:
- Minor (10-20% slower) — Windows scheduler/TLS overhead
- Major (50%+ slower) — CUDA driver differences, memory management
- Specific to certain configs — maybe `--n-cpu-moe` works worse on Windows

**We need to test and benchmark on our Windows setup before claiming any specific speed.**

---

## Validated Claims

These claims from CONFIG_GUIDE.md are **confirmed by Reddit evidence**:

| Claim | Verdict | Evidence |
|-------|---------|----------|
| ik_llama.cpp exists and is actively maintained | **Confirmed** | 2704 stars, updated daily |
| PR #1698 MTP for dense models merged | **Confirmed** | GitHub API verified |
| `--n-cpu-moe` flag works in ik_llama.cpp | **Confirmed** | Multiple posts reference it |
| `-fmoe` fused MoE ops | **Confirmed** | Referenced in ik_llama.cpp docs |
| MTP gives +27-30% on 27B dense | **Likely conservative** | Actual benchmarks show 27-150% depending on hardware |
| `-rtr` breaks GPU offload with cpu-moe | **Plausible** | Consistent with architecture, no counter-evidence |
| `_XL` GGUF incompatible with ik_llama | **Plausible** | IQ4_KS post explicitly uses i1 (ik_llama-specific) quants |
| TurboQuant repo exists with NextN + turbo3 KV | **Confirmed** | 252 stars, GitHub API verified |
| 35B MoE MTP not yet in ik_llama.cpp | **Confirmed** | PR #1698 title says "dense models only" |
| MTP GGUF required for MTP support | **Confirmed** | Multiple posts reference MTP-specific GGUFs |
| DDR4 matters less for image gen than text gen | **N/A** | Not tested in Qwen threads (relevant to Ideogram 4) |

---

## Unverified / Corrected Claims

| Claim in CONFIG_GUIDE | Verdict | Correction |
|----------------------|---------|------------|
| **"61 tok/s with n-cpu-moe 16 on RTX 5060 Ti"** (bobaburger) | **Unverified** | No Reddit post from "bobaburger" found. The number is plausible for DDR5 but untested on DDR4 + Windows. Should be marked as "reported, unverified" |
| **"74.7 tok/s with --fit no batch flags"** (bobaburger) | **Unverified** | Same source. Likely DDR5 Linux. Should be marked as "reported, unverified" |
| **"27B dense + MTP on ik_llama gives +27-30%"** | **Understated** | Actual benchmarks show wider range: 27% (2x RTX 3090) to 150% (Mac M2 Max). Depends heavily on hardware |
| **"Q4_K_M 35B scores 16/22"** | **Not in evidence** | The benchmark reference may be from an external site, not found in Reddit evidence |
| **"Q4_K_M + n-cpu-moe scores 22/22"** | **Not in evidence** | Same — the quality score reference is not verifiable from Reddit |
| Implied ik_llama works well on Windows | **Misleading** | Two Reddit comments explicitly report disappointing Windows performance. Should be flagged prominently |

---

## Key Insights for Our Setup

### RTX 5060 Ti 16GB + DDR4 + Windows 11

**What we know works (verified):**
- 27B IQ3_XXS at ~26 tok/s on upstream llama.cpp — our current default
- Models that fit entirely in VRAM (≤14GB) are dramatically faster
- MTP gives 1.5-2.5x speedup on compatible runtimes

**What we should test (evidence-supported but unverified on our hardware):**

1. **ik_llama.cpp + IQ4_KS + MTP on 27B** — Expected: 40-60 tok/s on Linux, unknown on Windows
   - If it works well on Windows, this is the biggest single upgrade
   - Pre-built Windows binaries exist (Thireus, X5R on HuggingFace)

2. **ik_llama.cpp + --n-cpu-moe 16 + -fmoe on 35B MoE** — Expected: 40-50 tok/s on Linux DDR5, maybe 30-40 on DDR4
   - The "61 tok/s" claim is unverified even on Linux for our specific hardware
   - `--n-cpu-moe` may interact badly with Windows memory management

3. **TurboQuant + NextN on 35B MoE** — Expected: +28-36% over baseline
   - Different codebase from ik_llama.cpp — can't mix them
   - turbo3 KV cache saves VRAM for longer context

**What to watch out for:**
- **Windows performance unknown** — must benchmark before relying on Linux numbers
- **DDR4 is our bottleneck** — all top benchmarks are DDR5 or unified memory
- **No bobaburger verification** — the 61/74.7 tok/s numbers should be treated as aspirational targets, not predictions

### Recommended Test Order

1. Download ik_llama.cpp Windows binary from [Thireus releases](https://github.com/Thireus/ik_llama.cpp/releases) or [X5R HuggingFace](https://huggingface.co/X5R/ik_llama.cpp)
2. Test 27B IQ3_XXS with same flags as our llama.cpp baseline — compare tok/s
3. If ik_llama is faster on Windows, download IQ4_KS model + MTP GGUF
4. Test 27B IQ4_KS + MTP on ik_llama.cpp
5. Test 35B Q4_K_M + --n-cpu-moe 16 + -fmoe on ik_llama.cpp
6. Document Windows-specific results — this data is missing from Reddit

---

## Evidence Sources

All JSON evidence files saved in `evidence/` directory.

| File | Post | Score |
|------|------|-------|
| post_1sn3izh_*.json | Qwen3.6-35B-A3B released! | 2302pts |
| post_1ssl1xh_*.json | Qwen 3.6 27B is out | 1721pts |
| post_1t57xuu_*.json | 2.5x faster MTP | 1233pts |
| post_1t82zxv_*.json | 80 tok/s 128K on 12GB | 675pts |
| post_1sxzqry_*.json | 27B BF16 vs Q4 vs Q8 eval | 718pts |
| post_1t0epei_*.json | 27B vs Gemma 4 | 986pts |
| post_1tjh7az_*.json | 110 tok/s ik_llama.cpp | 386pts |
| post_1tckzy2_*.json | MTP + TurboQuant | 385pts |
| post_1tipihx_*.json | 35B NTP vs MTP quant results | 261pts |
| post_1t5n672_*.json | 35B 20-34 t/s on 6GB | 294pts |
| post_1tgis7s_*.json | 27B on 24GB backend comparisons | 218pts |
| post_1tdns1i_*.json | 1M tokens testing 35B | 133pts |
| post_1tkmgwj_*.json | IQ4_KS for 16GB VRAM | 81pts |
| post_1ssilc3_*.json | 35B competitive with cloud | 726pts |
| post_1tf3p6c_*.json | Local vs frontier coding | 783pts |
| post_1ryze51_*.json | RTX 5060 Ti findings | 32pts |
| post_1so8253_*.json | Dual 5060 Ti cpu-moe | 22pts |
| post_1tx9ef5_*.json | 35B on RTX 3080 DDR5 | 15pts |
| post_1tryukc_*.json | Coding choice 27B vs 35B | 3pts |
| post_1qwo5ig_*.json | ik_llama Windows builds | 60pts |
| post_1mga3ox_*.json | Prebuilt Windows binary | 38pts |
| search_qwen36_top25.json | Broad search results | — |
| search_27b_speed_ik.json | 27B speed + ik_llama search | — |
| search_35b_speed.json | 35B speed search | — |
| search_27b_quants.json | 27B quant comparison search | — |
