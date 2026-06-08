# 27B Dense Optimization — Lessons Learned & Mistakes

## What I Got Wrong

### 1. Assumed IQ4_XS-MTP would fit 16GB VRAM

IQ4_XS-MTP is 14.4GB — looks like it fits. But the MTP draft model needs its own KV cache (f16 by default), and the target model needs KV cache for 64k context. Total VRAM needed:

- Model: 14.4GB
- Draft KV (f16): ~300MB
- Target KV (q4_0, 64k): ~1.1GB
- Total: ~15.8GB — barely fits, no headroom

In practice it overflowed and dropped to **0.70 tok/s**. The lesson: always calculate total VRAM including draft cache, not just model size.

### 2. Used -ngl 99 blindly instead of --fit on

Same mistake as 35B! With -ngl 99, llama.cpp tries to put ALL layers on GPU. If they don't fit, it silently offloads to CPU and destroys speed. With --fit on, it auto-calculates what fits.

But for IQ3_M-MTP (12GB), -ngl 99 works because the model + draft cache + KV fits. The fix was to use IQ3_M instead of IQ4_XS, not to add --fit.

### 3. ngram-mod stacking hurts on 27B MTP

I assumed ngram-mod + MTP would stack like on 35B. Wrong — on 27B where MTP already has decent acceptance (67%), the ngram search overhead reduces speed from 35→29 tok/s. The overhead of maintaining the ngram index outweighs the marginal acceptance improvement.

### 4. q4_0 draft KV cache hurts acceptance rate

I set -ctkd q4_0 -ctvd q4_0 to save VRAM. This reduced speed from 35→31 tok/s because the draft model's quantized predictions are less accurate, lowering acceptance. f16 draft cache is the default for a reason — the draft model needs precision to predict well.

### 5. Didn't optimize for long context stability

The short benchmark (150-220 tokens) showed 35.49 tok/s but a 300-token generation showed 23.49 tok/s. Multi-turn conversation is more realistic at 31 tok/s. The speed measurement matters — short bursts are misleading.

---

## What Actually Matters for 27B Dense on 16GB VRAM

### The VRAM budget is tight with MTP

| Component | IQ3_M-MTP | IQ4_XS-MTP |
|-----------|-----------|------------|
| Model weights | 12GB | 14.4GB |
| Draft KV (f16) | ~300MB | ~300MB |
| Target KV (q4_0, 64k) | ~1.1GB | ~1.1GB |
| **Total** | **~13.4GB** ✓ | **~15.8GB** ✗ |

IQ3_M-MTP leaves 2.6GB headroom. IQ4_XS-MTP leaves 0.2GB — any spike overflows.

### MTP acceptance rate depends on runtime

| Runtime | Acceptance | Source |
|---------|-----------|--------|
| ik_llama.cpp | 82-87% | janvitos, 386pts |
| upstream llama.cpp | ~67% | Our measurement |

ik_llama.cpp has better MTP acceptance because it optimizes the draft verification path. But it's 10x slower on Windows, so we can't use it.

### Long context behavior

Multi-turn is stable and actually improves slightly:
- Turn 1 (24 prompt tokens): 24.31 tok/s
- Turn 2 (183 prompt tokens): 31.17 tok/s (prompt cache helps)
- Turn 3 (338 prompt tokens): 31.94 tok/s (even better with cached context)

The KV cache at q4_0 is sufficient for 64k context quality on dense models. q8_0 is unnecessary for 27B — the DDR4 bottleneck doesn't exist since everything is in VRAM.

---

## KVarN — Not Available Yet in Upstream

Anbeeld's comment about "KVarN 4 goes hard" refers to KV cache quantization variants in his fork (beellama.cpp). These are NOT in upstream llama.cpp b9360. Available types in our build: `f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1`.

**What we should try for long context:**
- `iq4_nl` KV — 4-bit non-linear quant, may be better than q4_0 for long context quality
- Newer llama.cpp build (b9484+) — may include KVarN or better KV quants
- Anbeeld's beellama.cpp fork — has KVarN but needs building from source

---

## Methodology Rules for 27B

1. **Calculate total VRAM budget** — model + draft KV + target KV, not just model size
2. **Test with realistic multi-turn workloads** — short bursts overstate speed
3. **Don't stack speculative methods** — ngram + MTP can be worse than MTP alone
4. **Keep draft KV at f16** — quantizing the draft cache hurts acceptance
5. **For dense models in VRAM, q4_0 KV is fine** — unlike MoE where q8_0 is needed
6. **Use -ngl 99 only when you're sure it fits** — otherwise use --fit on
