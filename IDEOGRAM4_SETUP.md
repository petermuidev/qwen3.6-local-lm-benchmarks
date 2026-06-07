# Ideogram 4 Setup Plan — RTX 5060 Ti 16GB

## Current System State

| Item | Status |
|------|--------|
| Python | 3.11.9 ✓ |
| Git | 2.45.0 ✓ |
| PyTorch | 2.8.0 **CPU-only** (needs CUDA reinstall) |
| CUDA GPU | RTX 5060 Ti 16GB, driver 596.49 ✓ |
| Disk space | 222 GB free ✓ |
| ComfyUI | Not installed |

## Setup Steps

### Step 1: Install ComfyUI (portable — includes its own Python + CUDA PyTorch)

Use the **Windows portable** package. It ships its own Python + PyTorch+CUDA, so we don't need to mess with the system Python.

```powershell
cd C:\Users\Administrator\Desktop\cowork

# Download ComfyUI portable
Invoke-WebRequest -Uri "https://github.com/comfyanonymous/ComfyUI/releases/latest/download/ComfyUI_windows_portable_nvidia_cu124_or_cpu.7z" -OutFile "ComfyUI_portable.7z"

# Extract (needs 7-Zip)
# Install 7-Zip if not present: winget install 7zip.7zip
& "C:\Program Files\7-Zip\7z.exe" x ComfyUI_portable.7z -o"C:\Users\Administrator\Desktop\cowork\ComfyUI" -y

# Or use the direct zip if 7z is not available — download from ComfyUI releases page
```

**Portable structure:**
```
ComfyUI/
├── python_embeded/          # Bundled Python 3.11 + PyTorch+CUDA
├── ComfyUI/
│   ├── models/
│   │   ├── diffusion_models/  # ← put transformer here
│   │   ├── text_encoders/     # ← put Qwen3-VL here
│   │   ├── vae/               # ← put VAE here
│   │   └── ...
│   ├── custom_nodes/          # ← install KJNodes here
│   └── ...
├── run_nvidia_gpu.bat        # ← launch this
└── update/
```

### Step 2: Download Ideogram 4 models

**Recommended: FP8 + CFG=1 (3 files, ~18.8 GB)**

```powershell
# Create model directories
$Base = "C:\Users\Administrator\Desktop\cowork\ComfyUI\ComfyUI\models"
New-Item -ItemType Directory -Force -Path "$Base\diffusion_models"
New-Item -ItemType Directory -Force -Path "$Base\text_encoders"
New-Item -ItemType Directory -Force -Path "$Base\vae"

# Download FP8 transformer (8.64 GB)
Write-Host "Downloading ideogram4_fp8_scaled.safetensors (8.64 GB)..."
Invoke-WebRequest -Uri "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main/diffusion_models/ideogram4_fp8_scaled.safetensors" -OutFile "$Base\diffusion_models\ideogram4_fp8_scaled.safetensors"

# Download FP8 text encoder (9.86 GB)
Write-Host "Downloading qwen3vl_8b_fp8_scaled.safetensors (9.86 GB)..."
Invoke-WebRequest -Uri "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main/text_encoders/qwen3vl_8b_fp8_scaled.safetensors" -OutFile "$Base\text_encoders\qwen3vl_8b_fp8_scaled.safetensors"

# Download VAE (0.31 GB)
Write-Host "Downloading flux2-vae.safetensors (0.31 GB)..."
Invoke-WebRequest -Uri "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main/vae/flux2-vae.safetensors" -OutFile "$Base\vae\flux2-vae.safetensors"
```

**Optional: Also get NVFP4 for when you want to run llama-server + ComfyUI simultaneously:**
```powershell
# NVFP4 transformer (5.11 GB)
Invoke-WebRequest -Uri "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main/diffusion_models/ideogram4_nvfp4_mixed.safetensors" -OutFile "$Base\diffusion_models\ideogram4_nvfp4_mixed.safetensors"

# NVFP4 text encoder (5.87 GB)
Invoke-WebRequest -Uri "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main/text_encoders/qwen3vl_8b_nvfp4.safetensors" -OutFile "$Base\text_encoders\qwen3vl_8b_nvfp4.safetensors"
```

**Optional: Unconditional models for CFG=3 (only if you want full CFG):**
```powershell
# FP8 unconditional (8.64 GB)
Invoke-WebRequest -Uri "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main/diffusion_models/ideogram4_unconditional_fp8_scaled.safetensors" -OutFile "$Base\diffusion_models\ideogram4_unconditional_fp8_scaled.safetensors"

# NVFP4 unconditional (5.11 GB)
Invoke-WebRequest -Uri "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main/diffusion_models/ideogram4_unconditional_nvfp4_mixed.safetensors" -OutFile "$Base\diffusion_models\ideogram4_unconditional_nvfp4_mixed.safetensors"
```

### Step 3: Install KJNodes (for Prompt Builder)

```powershell
cd C:\Users\Administrator\Desktop\cowork\ComfyUI\ComfyUI\custom_nodes

# Use the portable Python for pip
$Python = "..\..\python_embeded\python.exe"

git clone https://github.com/kijai/ComfyUI-KJNodes.git
& $Python -m pip install -r ComfyUI-KJNodes\requirements.txt
```

### Step 4: Launch ComfyUI

**Before launching — stop llama-server first** (one LLM at a time):

```powershell
# Stop text generation
taskkill /F /IM llama-server.exe

# Start ComfyUI
cd C:\Users\Administrator\Desktop\cowork\ComfyUI
.\run_nvidia_gpu.bat
```

ComfyUI web interface opens at `http://127.0.0.1:8188`

### Step 5: Load Ideogram 4 workflow

1. Open browser → `http://127.0.0.1:8188`
2. Click **Load** → browse for the Ideogram 4 default workflow (included in ComfyUI templates)
3. Or: use Kijai's Prompt Builder workflow from the KJNodes examples

**Key settings to change from defaults:**
- Set CFG to **1** (skip unconditional model = half VRAM + half time)
- Set steps to **12** (Turbo mode)
- Set resolution to **512x512** (generate small, upscale later)
- Or: use FluxResolutionNode for other aspect ratios

### Step 6: Generate images

**Method A: Kijai Prompt Builder (easiest)**
1. Add "Ideogram 4 Prompt Builder" node from KJNodes
2. Draw bounding boxes on the visual canvas
3. Type descriptions per element
4. Click generate

**Method B: Generate Text node (auto-JSON)**
1. Add "Generate Text" node to workflow
2. Connect it before the CLIPTextEncode node
3. Type your idea in plain text
4. The Qwen3-VL text encoder converts it to JSON automatically

**Method C: External 27B IQ3_XXS (best quality)**
1. Stop ComfyUI
2. Start llama-server (`start-server-27b-iq3xxs.ps1`)
3. Ask 27B to generate Ideogram JSON:
   ```
   Convert this to Ideogram 4 JSON format: "a beach party poster with palm trees"
   Return ONLY the JSON with high_level_description, style_description, 
   and compositional_deconstruction with bounding boxes.
   ```
4. Copy the JSON output
5. Stop llama-server, start ComfyUI
6. Paste JSON into the prompt node

### Step 7: Switching back to text generation

```powershell
# Close ComfyUI browser tab
# Kill ComfyUI process
taskkill /F /IM python.exe

# Restart llama-server
cd C:\Users\Administrator\Desktop\cowork\llama-qwen3.6-mtp
.\start-server-27b-iq3xxs.ps1
```

---

## Quick Reference: Mode Switching

| Switch to | Commands |
|-----------|----------|
| **Text mode** | `taskkill /F /IM python.exe` → `.\start-server-27b-iq3xxs.ps1` |
| **Image mode** | `taskkill /F /IM llama-server.exe` → `cd ComfyUI` → `.\run_nvidia_gpu.bat` |

---

## Disk Budget

| Item | Size | Running Total |
|------|------|---------------|
| ComfyUI portable | ~5 GB | 5 GB |
| Ideogram 4 FP8 (3 files, CFG=1) | 18.8 GB | 23.8 GB |
| Optional: NVFP4 set | 11.3 GB | 35.1 GB |
| Optional: Unconditional FP8 | 8.64 GB | 43.7 GB |
| Optional: Unconditional NVFP4 | 5.11 GB | 48.8 GB |
| **Minimum (FP8 + CFG=1)** | **~24 GB** | |
| **Full set (all quants + CFG=3)** | **~49 GB** | |

Available: 222 GB → plenty of room even for full set.

---

## VRAM Budget During Image Generation

### FP8 + CFG=1 (recommended — no offload during sampling)

```
Phase 1: Text encoding
  VRAM: Qwen3-VL FP8 (9.86 GB) + VAE (0.31 GB) = 10.17 GB
  Duration: ~10-30 seconds (one time)

Phase 2: Swap text encoder out
  VRAM: 0.31 GB (VAE only)
  Duration: ~1-2 seconds (DDR4 copy to RAM)

Phase 3: Sampling (12 steps, ALL in VRAM — zero DDR4!)
  VRAM: Transformer FP8 (8.64 GB) + VAE (0.31 GB) + activations (~1 GB) = ~10 GB
  Duration: ~30-60 seconds at 512x512

Phase 4: VAE decode
  VRAM: VAE (0.31 GB) + output image
  Duration: ~2-5 seconds

Peak: ~10.17 GB → 16 GB - 10 = 6 GB headroom ✓
```

### NVFP4 + CFG=1 (if you want to keep llama-server running)

```
Phase 1: Text encoding
  VRAM: Qwen3-VL NVFP4 (5.87 GB) + VAE (0.31 GB) = 6.18 GB
  llama-server: 11.17 GB
  Total: 17.35 GB → OVER 16 GB

  Must stop llama-server first, or accept heavy offload.
  Recommend: stop llama-server for image generation.
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Out of memory" during text encoding | Use NVFP4 text encoder instead of FP8 (saves 4 GB) |
| Safety filter blocks everything | Use JSON prompting with KJNodes Prompt Builder — add more bounding boxes and detail |
| Generation too slow | Set CFG=1, reduce to 12 Turbo steps, use 512x512 then upscale |
| ComfyUI won't start | Check `run_nvidia_gpu.bat` — make sure no other process uses VRAM |
| VRAM not freeing after ComfyUI close | Kill python.exe process manually |
| Images look wrong / garbled | Make sure you're using JSON prompt format, not raw text |
| Missing nodes after update | Run `.\update\update_comfyui.bat` then restart |

---

## What's NOT needed

- ❌ Ollama (Generate Text node or external 27B handles JSON)
- ❌ System PyTorch CUDA (portable has its own)
- ❌ Unconditional model (CFG=1 skips it)
- ❌ 24GB GPU (FP8 + CFG=1 fits 16GB)
- ❌ DDR5 RAM (no offload during sampling = DDR4 is fine)
