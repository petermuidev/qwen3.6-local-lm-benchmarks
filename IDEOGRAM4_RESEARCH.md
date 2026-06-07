# Ideogram 4 on RTX 5060 Ti 16GB — Research Findings & Setup Guide

## TL;DR

Ideogram 4 can run on 16GB VRAM. The key discoveries: (1) JSON prompting is mandatory, not optional — raw text produces garbage + safety blocks; (2) Setting CFG=1 eliminates the unconditional transformer, cutting VRAM and time in half; (3) NVFP4 quant (~5GB/model) fits with sequential offload; (4) FP8 + CFG=1 fits with NO offload during sampling; (5) The "censorship" is mostly a prompt format issue, bypassed by structured JSON with bounding boxes.

---

## Model Architecture (6 Components)

| # | Component | Purpose | FP8 Size | NVFP4 Size |
|---|-----------|---------|----------|------------|
| 1 | **Transformer (DiT)** | 34-layer single-stream diffusion model. Generates latents from text conditioning. | 8.64 GB | 5.11 GB |
| 2 | **Unconditional Transformer** | CFG companion. Same DiT architecture but runs with empty conditioning (drops all text tokens). **Optional — set CFG=1 to skip entirely.** | 8.64 GB | 5.11 GB |
| 3 | **Text Encoder** | Qwen3-VL-8B-Instruct. Encodes prompts using hidden states from **13 intermediate layers** (not just final layer — unique to Ideogram 4). | 9.86 GB | 5.87 GB |
| 4 | **VAE** | Flux2 VAE (shared with Flux.2 models). Latent-to-pixel decoder. Tiny. | 0.31 GB | 0.31 GB |
| 5 | Tokenizer | Text tokenization config | ~0.01 GB | — |
| 6 | Scheduler | Diffusion timestep scheduling config | ~0.01 GB | — |

**Total FP8 (all 4 loaded):** ~27.5 GB — doesn't fit 16GB
**Total NVFP4 (all 4 loaded):** ~16.4 GB — barely over 16GB, no room for activations
**Total FP8 + CFG=1 (3 files, unconditional skipped):** ~18.8 GB — fits with sequential offload
**Total NVFP4 + CFG=1 (3 files):** ~11.3 GB — fits easily

### Architecture Notes (from ComfyOrg official announcement)

- 34-layer single-stream DiT, 9.3B parameters
- Qwen3-VL-8B-Instruct as text encoder, consuming hidden states from 13 intermediate layers
- Asymmetric CFG: unconditional pass drops text tokens entirely to speed up sampling
- Single set of weights handles all resolutions (ultra-wide banners to phone wallpapers) — no LoRA needed
- X-Omni English OCR accuracy: 0.97
- #1 open-weights on designer preference ELO, beating FLUX 2 [dev] and Nano Banana 2
- Trained exclusively on structured JSON captions — **this is not a text-prompt model**

---

## The 5 Critical Findings from Reddit Research

### Finding 1: JSON Prompting Is Not Optional

Source: u/DsDman (r/StableDiffusion)

> "Ideogram4's JSON format is definitely a must, you get terrible results and random censorship when not using it."

The model was trained exclusively on structured JSON captions. Raw text prompts produce:
- Garbage quality images
- Frequent "safety filter" blocks (grey output)
- Unpredictable composition

The JSON format includes:
- `high_level_description`: 80-word scene overview
- `style_description`: aesthetics, lighting, photo style, medium, hex color palette (3-8 colors)
- `compositional_deconstruction`: elements with bounding boxes `[y_min, x_min, y_max, x_max]` using 0-1000 coordinates, typed as `obj` or `text`

**Lesson**: Never use raw text with Ideogram 4. Always use JSON.

### Finding 2: The "Censorship" Is Mostly a Prompt Format Problem

Source: u/afinalsin (detailed analysis), u/Omegapepper, u/PassTheMarsupial

The model's safety behavior works like an LLM refusing prompts — it's probability-based, not hard-coded anatomy butchery:

- Short prompts with trigger-heavy keywords → safety training "wins" the probability → grey block
- JSON with lots of benign descriptive detail → benign tokens outweigh triggers 7:2 → model generates normally
- It's NOT SD3-style butchered anatomy. When it does generate, anatomy is perfect.
- It's NOT heavy-handed purity enforcement. More like "doesn't have that information" probability suppression.

From u/PassTheMarsupial:
> "Literally if you put your request into the JSON format the model gives you the output."

From u/Omegapepper:
> "Only if prompting with natural language which the model cannot handle. Not with proper json prompting."

**Bypass strategy** (from u/afinalsin):
- Fill the JSON with lots of detailed, benign scene elements (background, lighting, environment, supporting objects)
- The more tokens in the prompt, the lower the probability that the safety token "wins"
- Multiple bounding boxes with different elements dilutes focus on any single trigger concept

**Lesson**: "Censorship" is a prompt engineering issue, not a model capability issue. Use proper JSON with rich detail.

### Finding 3: Kijai's Prompt Builder Node Is the Killer Tool

Source: u/Ok_Conference_7975, u/GrayingGamer, Kijai himself (r/StableDiffusion)

Kijai (ComfyUI team member) built the **Ideogram 4 Prompt Builder** within **one day** of release. It's in the KJNodes pack.

Features:
- Visual canvas to draw bounding boxes (no manual coordinate calculation)
- Type element descriptions per box
- Set color palettes
- Auto-generates the JSON prompt

From Kijai:
> "I've always enjoyed control over anything else so this model hits that spot for me, probably best regional prompting I've experienced."

From u/diogodiogogod:
> "Drawing bounding boxes I almost never get censored."

**Alternative tools**:
- [ideogram4-editor](https://d-daley.github.io/ideogram4-editor/) by u/DsDman — standalone web tool with same box-drawing concept ([GitHub](https://github.com/d-daley/ideogram4-editor))
- Both tools were independently built by users who had the same idea the same day

**Lesson**: Don't type JSON manually. Use a visual builder.

### Finding 4: Generate Text Node + Qwen 8B for Auto-JSON Inside ComfyUI

Source: u/1filipis (r/StableDiffusion)

You can use ComfyUI's built-in **Generate Text** node with the same Qwen3-VL-8B text encoder that Ideogram already requires. No external Ollama or LLM needed.

Settings:
```
max_length: 600
top_k: 20
top_p: 0.8
repetition_penalty: 1.0
temperature: 0.7
```

**Important**: Switch `Load CLIP` to `stable_diffusion` mode.

Tradeoffs:
- Advantage: No extra model to download, no Ollama dependency, everything stays in ComfyUI
- Disadvantage: Low variance — JSON is very specific, so you need to regenerate if blocked
- The text encoder does double duty: generates JSON prompt AND conditions the diffusion model

**Alternative**: Use your local 27B IQ3_XXS (already running on llama-server) to convert natural language → Ideogram JSON format. Better quality JSON, but requires external call.

**Lesson**: The text encoder can generate JSON prompts too — no separate LLM strictly required.

### Finding 5: CFG=1 Eliminates the Unconditional Transformer

Source: u/Early-Ad-1140, u/Last-Trash-7960 (r/StableDiffusion)

From u/Early-Ad-1140:
> "Crank down CFG to 1. The quality drop is minimal and prompt adherence is a bit worse but generation times are cut in half."

From u/Last-Trash-7960:
> "You dont need the unconditional."

Setting CFG=1 means:
- **No unconditional forward pass per step** — skip the 8.64GB/5.11GB unconditional model entirely
- **VRAM cut in half** — only the main transformer needs to be in VRAM
- **Generation time cut in half** — one forward pass per step instead of two
- Slight quality tradeoff but "minimal" per users

u/Succubus-Empress noted: *"Its double, 18.6B, you forgot to count unconditional model that is another 9.3B"*

u/LumaBrik: *"there is an nvfp4 version of the unconditional model at just over 5Gb, which works well, instead of the 9gb version."*

**Lesson**: For bandwidth-constrained hardware, CFG=1 is the single biggest optimization. It removes half the compute and half the VRAM requirement.

---

## VRAM Budget — All Configurations

### Option A: FP8 + CFG=1 — NO offloading during sampling (RECOMMENDED for quality)

| Phase | In VRAM | In RAM |
|-------|---------|--------|
| Text encoding | Text encoder FP8 (9.86 GB) + VAE (0.31 GB) | — |
| After encoding | VAE (0.31 GB) | Text encoder offloaded (~10 GB) |
| Sampling (all 12 steps) | Transformer FP8 (8.64 GB) + VAE (0.31 GB) + activations (~1 GB) | Text encoder stays in RAM |
| VAE decode | VAE (0.31 GB) + output | Transformer offloaded |

**Peak VRAM: ~10 GB** — fits in 16GB with zero DDR4 offload during sampling

Download: 3 files = ~18.8 GB
- `diffusion_models/ideogram4_fp8_scaled.safetensors` (8.64 GB)
- `text_encoders/qwen3vl_8b_fp8_scaled.safetensors` (9.86 GB)
- `vae/flux2-vae.safetensors` (0.31 GB)

### Option B: NVFP4 + CFG=1 — maximum VRAM headroom

| Phase | In VRAM | In RAM |
|-------|---------|--------|
| Text encoding | Text encoder NVFP4 (5.87 GB) + VAE (0.31 GB) | — |
| After encoding | VAE (0.31 GB) | Text encoder offloaded |
| Sampling (all steps) | Transformer NVFP4 (5.11 GB) + VAE (0.31 GB) + activations | Text encoder in RAM |
| VAE decode | VAE (0.31 GB) | Transformer offloaded |

**Peak VRAM: ~6.2 GB** — massive headroom, could run alongside llama-server

Download: 3 files = ~11.3 GB

### Option C: NVFP4 + CFG=3 + sequential offload — best quality with CFG

| Phase | In VRAM | In RAM |
|-------|---------|--------|
| Text encoding | Text encoder NVFP4 (5.87 GB) + VAE (0.31 GB) | — |
| Sampling step (conditional) | Transformer NVFP4 (5.11 GB) + VAE (0.31 GB) | Text encoder + unconditional in RAM |
| Sampling step (unconditional) | Unconditional NVFP4 (5.11 GB) + VAE (0.31 GB) | Text encoder + transformer in RAM |
| VAE decode | VAE (0.31 GB) | All transformers offloaded |

**Peak VRAM: ~6.2 GB** — always fits, but model swapping per step on DDR4

Download: 4 files = ~16.4 GB

### Option D: FP8 + CFG=3 + sequential offload — best quality, slower

Peak VRAM: ~9 GB per phase. Fits in 16GB with sequential swap.
Download: 4 files = ~27.5 GB (all FP8)

---

## Speed Benchmarks from Reddit

| GPU | Config | Steps | Resolution | Time | Source |
|-----|--------|-------|-----------|------|--------|
| RTX 5090 | FP8 | 28 | 1024x1024 | 20-30s | u/durden111111 |
| RTX 3090 | FP8 | 28 | 1MP | 105s | u/GlibGentleman |
| RTX 3080 Ti 16GB | FP8 + offload | 12 (Turbo) | 1024x1024 | ~60s | u/sci032 |
| RTX 2070 8GB | NVFP4 + RAM offload | 28 | ? | "not my friend" | u/v3lh0t05c0 |
| Slower GPU | ? | 28 | ? | 10 min | u/cathodeDreams |
| General estimate | — | 28 | — | 3-5 min | u/cadissimus |

### Estimated performance on RTX 5060 Ti 16GB + DDR4

| Config | Steps | Resolution | Est. Time | Notes |
|--------|-------|-----------|-----------|-------|
| FP8 + CFG=1, Turbo | 12 | 512x512 | ~30-60s | No offload during sampling! |
| FP8 + CFG=1, Turbo | 12 | 1024x1024 | ~2-3 min | More activations, still no offload |
| NVFP4 + CFG=3, Turbo | 12 | 512x512 | ~2-4 min | Sequential offload per step on DDR4 |
| NVFP4 + CFG=3, Standard | 28 | 1024x1024 | ~5-8 min | Double steps + offload |
| FP8 + CFG=1, Standard | 28 | 1024x1024 | ~3-5 min | No offload, but more steps |

**Key insight**: With CFG=1, the sampling loop runs entirely in VRAM (no DDR4 transfer per step). This is the same principle as llama.cpp — DDR4 offload is the killer, and avoiding it changes everything.

---

## Offload Mechanics (How ComfyUI Handles <VRAM)

Source: u/boffeez, u/roxoholic, u/Eisenstein, u/SymphonyofForm (r/ComfyUI)

**How it works**:
1. ComfyUI loads as much of the model into VRAM as possible
2. Excess weights stay in system RAM
3. During sampling, needed chunks are transferred RAM→VRAM per step
4. Each step requires ~4GB transfer (for a model that doesn't fit)

**DDR4 vs DDR5 impact**:
- With optimized offloading, RAM→VRAM transfer cost can be **hidden behind GPU compute** (overlapped)
- DDR4 speed matters less than PCIe bandwidth for the actual transfer
- RTX 5060 Ti uses PCIe 5.0 x8 = 32 GB/s bandwidth
- DDR4-3200 dual channel = ~51 GB/s bandwidth
- PCIe is the bottleneck for transfer, not RAM speed
- BUT: CPU must prepare data before it can be sent over PCIe — slow RAM can cause PCIe idle time

**u/roxoholic's real test**: SDXL (6GB model) on 4GB VRAM — swapped 2-3GB per step, 2-3 times per step

**u/boffeez**: With optimized offloading, transfer time can be hidden behind GPU compute, making it "no difference to total generation time"

**Lesson**: DDR4 matters less for image generation than for text generation because:
1. Image models transfer weights per step (not per token)
2. Transfer can overlap with GPU compute
3. Steps are fewer (12-28) vs tokens (hundreds-thousands)
4. Our DDR4 nightmare is mainly a *text generation* problem

---

## Creative Workflows from the Community

### Workflow 1: QwenVL + Image Input → JSON Prompt → Ideogram 4

Source: u/sci032 (r/ComfyUI, RTX 3080 Ti 16GB)

- Load input image → resize to 75% (save LLM memory)
- Send to Qwen3-VL-8B via Ollama with art director system prompt
- QwenVL generates structured JSON with hex palettes, bounding boxes, scene descriptions
- Feed JSON into Ideogram 4 for generation
- 512x512 generation → PID upscale to 2048x2048
- ~1 minute total on 16GB VRAM in Turbo mode

**System prompt for QwenVL** (from u/sci032):
```
You are a visual art director and scene specification engine.
Do not merely extract the prompt. Act as an experienced art director.
Expand sparse prompts into visually rich compositions while preserving the user's intent.
Infer missing details when needed, including:
- style, materials, lighting, textures, composition, typography, color palette, supporting visual elements
Reasonable embellishments may be added if they strengthen the design.

OUTPUT: Return exactly one JSON object. No markdown. No code fences. No explanations.
Schema:
{
  "high_level_description":"...",
  "style_description":{"aesthetics":"...","lighting":"...","photo":"...","medium":"...","color_palette":[]},
  "compositional_deconstruction":{"background":"...","elements":[]}
}
```

### Workflow 2: Double-Pass LLM for Better JSON

Source: u/Ssm5969 (r/ComfyUI)

- **Phase 1**: Qwen3-VL abliterated 8B via Ollama — raw visual analysis from input image
- **Phase 2**: Same LLM, second pass — reformulates and optimizes JSON specifically for Ideogram 4 schema
- **Phase 3**: Ideogram 4 generation with DualModelGuider

Uses `huihui_ai/qwen3-vl-abliterated:8b-instruct` via Ollama (uncensored version of Qwen3-VL).

Ollama settings: `temperature: 0.1, repeat_penalty: 1.1, top_k: 40, top_p: 0.9, num_ctx: 16384`

### Workflow 3: Generate Text Node (No External LLM)

Source: u/1filipis (r/StableDiffusion)

Simplest approach — just two nodes added to default Ideogram template:
- Generate Text node using the same Qwen3-VL text encoder (already loaded for Ideogram)
- Switch Load CLIP to `stable_diffusion` mode
- `max_length: 600, temperature: 0.7, top_k: 20, top_p: 0.8`

No Ollama, no external dependencies. The text encoder does double duty.

### Workflow 4: External 27B LLM → JSON → ComfyUI API

Source: u/Producing_It (r/StableDiffusion)

> "I use qwen 3.6 27B to convert my natural writing and even images into JSON text."

Use your already-running 27B IQ3_XXS to convert natural language → Ideogram JSON, then:
- Option 1: Copy-paste JSON into ComfyUI
- Option 2: Use the [ideogram4-editor](https://d-daley.github.io/ideogram4-editor/) tool which can call ComfyUI's API directly
- Option 3: ComfyUI API endpoint for automated pipeline

**This is the best option for our setup** — the 27B is already running, produces higher-quality JSON than the 8B encoder, and we understand its behavior from the Qwen3.6 benchmarks.

---

## ComfyUI Sampler Settings

From community benchmarks and ComfyOrg defaults:

| Setting | Turbo (fast) | Standard (quality) |
|---------|-------------|-------------------|
| Sampler | Euler | Euler |
| Scheduler | BasicScheduler (simple) | BasicScheduler (simple) |
| Steps | **12** | 28 |
| CFG | **1** (fastest) or 3 (quality) | 3 |
| distilled_cfg | 0.9 | 0.9 |
| ModelSamplingAuraFlow | shift=5 | shift=5 |
| Resolution | 512x512 → upscale | 1024x1024 or larger |
| Latent | EmptyFlux2LatentImage | EmptyFlux2LatentImage |
| VAE | flux2-vae.safetensors | flux2-vae.safetensors |

**Speed trick from u/Early-Ad-1140**: CFG=1 cuts time in half (no unconditional pass). Quality drop is minimal.

**Upscale strategy from u/sci032**: Generate at 512x512 then PID upscale to 2048x2048. Faster than generating at high res directly.

---

## Installation Checklist

### 1. Download models from Comfy-Org/Ideogram-4 on HuggingFace

**Option A: FP8 + CFG=1 (recommended — best quality, no offload)**
```
ComfyUI/models/diffusion_models/ideogram4_fp8_scaled.safetensors         (8.64 GB)
ComfyUI/models/text_encoders/qwen3vl_8b_fp8_scaled.safetensors           (9.86 GB)
ComfyUI/models/vae/flux2-vae.safetensors                                  (0.31 GB)
Total: ~18.8 GB (3 files)
```

**Option B: NVFP4 + CFG=1 (maximum headroom, slight quality tradeoff)**
```
ComfyUI/models/diffusion_models/ideogram4_nvfp4_mixed.safetensors         (5.11 GB)
ComfyUI/models/text_encoders/qwen3vl_8b_nvfp4.safetensors                (5.87 GB)
ComfyUI/models/vae/flux2-vae.safetensors                                  (0.31 GB)
Total: ~11.3 GB (3 files)
```

**Option C: NVFP4 + CFG=3 (full CFG, sequential offload)**
```
Same as Option B plus:
ComfyUI/models/diffusion_models/ideogram4_unconditional_nvfp4_mixed.safetensors  (5.11 GB)
Total: ~16.4 GB (4 files)
```

**Option D: FP8 + CFG=3 (best quality, slowest)**
```
Same as Option A plus:
ComfyUI/models/diffusion_models/ideogram4_unconditional_fp8_scaled.safetensors   (8.64 GB)
Total: ~27.5 GB (4 files)
```

### 2. Install KJNodes for Prompt Builder

```
cd ComfyUI/custom_nodes
git clone https://github.com/kijai/ComfyUI-KJNodes
```

### 3. Optional: Install Ollama for external JSON generation

```
# Install Ollama: https://ollama.com
ollama pull huihui_ai/qwen3-vl-abliterated:8b-instruct
```

Or use the comfyui-ollama custom node:
```
cd ComfyUI/custom_nodes
git clone https://github.com/stavsap/comfyui-ollama
```

### 4. Alternative: Use ideogram4-editor web tool

- Web: https://d-daley.github.io/ideogram4-editor/
- GitHub: https://github.com/d-daley/ideogram4-editor
- Can call ComfyUI API directly for automated generation

---

## DDR4 vs DDR5 Context for Image Generation

From the offloading discussion (r/ComfyUI), DDR4 matters LESS for image generation than for text generation:

| Factor | Text Generation (llama-server) | Image Generation (ComfyUI) |
|--------|-------------------------------|---------------------------|
| Transfer unit | Per token (~100ms intervals) | Per step (~2-5s intervals) |
| Transfer frequency | Hundreds-thousands of times | 12-28 times |
| Overlap potential | Low (tokens are sequential) | High (GPU compute overlaps transfer) |
| DDR4 impact | **Severe** (5 tok/s at 39K context) | **Moderate** (~2x slower, not 10x) |
| PCIe bottleneck | Rarely (small chunks) | Possible (4GB chunks per step) |

**Lesson**: Our DDR4 nightmare is primarily a text-generation problem. For image generation with CFG=1 (no offload during sampling), DDR4 barely matters because the transformer runs entirely in VRAM for all steps. The DDR4 transfer only happens once: loading the text encoder, encoding the prompt, then swapping it out before sampling begins.

---

## Summary Table: What to Download & Run

| Goal | Files | Total Size | CFG | Steps | Est. Speed |
|------|-------|-----------|-----|-------|-----------|
| Best quality, fast | FP8 transformer + FP8 text enc + VAE | 18.8 GB | 1 | 12 Turbo | ~30-60s/512px |
| Best quality, full CFG | All 4 FP8 files | 27.5 GB | 3 | 12 Turbo | ~2-4 min/512px |
| Smallest download | NVFP4 transformer + NVFP4 text enc + VAE | 11.3 GB | 1 | 12 Turbo | ~1-2 min/512px |
| Full CFG, budget | All 4 NVFP4 files | 16.4 GB | 3 | 12 Turbo | ~2-4 min/512px |

**Recommendation for RTX 5060 Ti 16GB**: Start with Option A (FP8 + CFG=1). If quality is insufficient, add the unconditional model for CFG=3. The NVFP4 option is only needed if you want to run llama-server and ComfyUI simultaneously (~6.2 GB VRAM for image gen leaves ~10 GB for text model).

---

## Sources

- [Comfy-Org/Ideogram-4 on HuggingFace](https://huggingface.co/Comfy-Org/Ideogram-4) — repackaged model files
- [Ideogram 4.0 Just Open Sourced! — ComfyOrg announcement](https://old.reddit.com/r/comfyui/comments/1tvttzv/ideogram_40_just_open_sourced/) — architecture details, official specs
- [Ideogram 4 is pretty good — you just really have to use their JSON format](https://www.reddit.com/r/StableDiffusion/comments/1twqyrf/) — JSON format necessity, ideogram4-editor tool
- [Ideogram tip: use Generate Text node to make JSON](https://www.reddit.com/r/StableDiffusion/comments/1txmpbi/) — Generate Text node approach, censorship analysis
- [OK Ideogram 4.0 is Pretty Fun Actually!](https://www.reddit.com/r/StableDiffusion/comments/1twv7ec/) — Kijai Prompt Builder, CFG=1 speed trick, benchmark data
- [Ideogram 4 (lower vram workflow)](https://old.reddit.com/r/comfyui/comments/1twi4vq/) — NVFP4 approach, deconstructed subgraph workflow
- [Does offloading to RAM happen once per phase?](https://old.reddit.com/r/comfyui/comments/1tsma4o/) — offload mechanics, DDR4 vs DDR5 impact
- [Interesting thing to do with Ideogram-4 using QwenVL and an image](https://old.reddit.com/r/comfyui/comments/1tz5h3z/) — RTX 3080 Ti 16GB benchmark, Turbo 12-step, art director prompt
- [Local & Uncensored Img2Img with Qwen3-VL Abliterated 8B](https://old.reddit.com/r/comfyui/comments/1tye5zw/) — double-pass LLM workflow, full technical stack
- [Kijai's KJNodes](https://github.com/kijai/ComfyUI-KJNodes) — Ideogram Prompt Builder node
- [ideogram4-editor](https://github.com/d-daley/ideogram4-editor) — standalone JSON prompt builder
