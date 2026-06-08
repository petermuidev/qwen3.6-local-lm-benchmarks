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

### 6. Context size IS the VRAM budget — the biggest discovery

I spent hours testing KV quant types (q4_0, q8_0, iq4_nl) and --fit vs -ngl 99, trying to get 27B stable at long context with 64K context. Everything was slow (13 t/s). The real problem was the 64K context itself.

`--fit on` with 64K context reserves VRAM for the full 64K KV cache upfront. This forces model layers to CPU. Result: 13 t/s even at short context because layers are already offloaded.

The fix: reduce context to 16K. At 16K, IQ3_XXS (11.2GB) + KV (~1.2GB) = ~12.4GB total. All layers fit in GPU. Speed jumps to 26-28 t/s.

| Context Size | VRAM Used | Speed | Layers on GPU |
|-------------|-----------|-------|---------------|
| 16K | 12.4GB | 26 t/s | All |
| 32K | 12.7GB | 22 t/s | Most |
| 64K | 14.3GB | 13 t/s | Few |

**Lesson**: For dense models on 16GB VRAM, context size is the primary speed control. Don't blindly use 64K context — use the smallest context that covers your use case.

### 7. MTP makes long context worse, not better

MTP gives 35.49 t/s at short context (1.79x speedup) but at 4K+ context the draft cache (~300MB f16) steals VRAM from the growing KV cache. Speed collapses to 10-17 t/s. Dropping MTP for long context gives ~26 t/s stable at 15K.

The right approach: two configs. `start-server-27b.ps1` (MTP, short chats) and `start-server-27b-longctx.ps1` (no MTP, 16K context, long sessions).

### 8. q8_0 KV vs q4_0 KV — only matters at 64K context

At 64K context, q8_0 KV was better (25 t/s vs 22 t/s at 20K). But at 16K context where everything fits in VRAM, q4_0 is the right choice because it keeps total VRAM lower (~12.4GB vs ~13.5GB), ensuring all layers stay on GPU.

The KV quant choice depends on whether you're VRAM-constrained. At 16K ctx, q4_0 wins. At 64K ctx (slow anyway), q8_0 wins.

### 9. iq4_nl KV is catastrophically slow

Tried iq4_nl (4-bit non-linear quant) hoping for better quality at 4-bit size. Result: 8 t/s at just 5K context. The decompression overhead is enormous. Available KV types ranked for speed:

1. q4_0 (best when VRAM-constrained — keeps total low)
2. q8_0 (best for long context when not VRAM-constrained)
3. f16 (default, accurate but huge)
4. iq4_nl (terrible — avoid for generation)

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

1. **Context size is the primary speed control** — smaller ctx = less KV reservation = more GPU layers. 16K gives 26 t/s, 64K gives 13 t/s
2. **Calculate total VRAM budget** — model + KV cache (at chosen context size), not just model size
3. **Test with realistic multi-turn workloads** — short bursts overstate speed
4. **Don't stack speculative methods** — ngram + MTP can be worse than MTP alone
5. **Keep draft KV at f16** — quantizing the draft cache hurts acceptance
6. **q4_0 KV when VRAM-constrained, q8_0 when not** — at 16K ctx q4_0 keeps total low; at 64K ctx q8_0 decompresses faster
7. **MTP is short-context only on 16GB VRAM** — draft cache steals KV VRAM at long context
8. **iq4_nl KV is unusable** — 8 t/s at 5K, decompression overhead destroys speed
9. **Two configs needed** — MTP for short chats, no-MTP + 16K ctx for long sessions
10. **Don't blindly use 64K context** — use the smallest context that covers your use case
