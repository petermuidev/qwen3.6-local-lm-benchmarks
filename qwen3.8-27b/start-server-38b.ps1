$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LlamaDir = Join-Path $Root "llama.cpp-b10437-cuda12"
$ServerExe = Join-Path $LlamaDir "llama-server.exe"
$ModelPath = Join-Path $Root "models\Qwen3.8-27B-GGUF\Qwen3.8-27B-UD-IQ3_XXS.gguf"

if (-not (Test-Path $ServerExe)) {
    throw "Missing llama-server.exe at $ServerExe"
}
if (-not (Test-Path $ModelPath)) {
    throw "Missing model at $ModelPath. Download with: hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-IQ3_XXS.gguf --local-dir models\Qwen3.8-27B-GGUF"
}

# ═══ Production config for Qwen3.8-27B + MTP (HF discussion #26 replica) ═══
# Proven: ~53 t/s at 94K context on RTX 5060 Ti 16GB + 32GB RAM
# Key ingredients:
#   - draft-mtp draft-max=3: 35 -> 50-55 t/s
#   - q4_0 KV: keeps 94K context KV in VRAM
#   - --load-mode none --no-mmap --fit off: all layers forced to GPU
#   - reasoning_effort=medium: default xhigh makes the model overthink
#   - preserve-thinking: keeps reasoning context between turns
#
# VRAM math (16GB):
#   IQ3_XXS target: 11.9 GB
#   MTP draft head: ~0.3 GB
#   KV q4_0 at 94K: ~3.3 GB
#   Total: ~15.5 GB -> fits, but tight. Close other GPU apps.
#
# Draft-max tradeoff (from Qwen3.6 lessons):
#   draft-max=3 corrupts tool-call JSON when drafts are rejected mid-JSON.
#   Set $env:LLAMA_DRAFT_MAX="1" for opencode/coding agent sessions.

$Context    = if ($env:LLAMA_CONTEXT)  { $env:LLAMA_CONTEXT }  else { "94208" }
$Port       = if ($env:LLAMA_PORT)     { $env:LLAMA_PORT }     else { "8080" }
$HostAddr   = if ($env:LLAMA_HOST)     { $env:LLAMA_HOST }     else { "127.0.0.1" }
$Threads    = if ($env:LLAMA_THREADS)  { $env:LLAMA_THREADS }  else { "16" }
$DraftMax   = if ($env:LLAMA_DRAFT_MAX) { $env:LLAMA_DRAFT_MAX } else { "3" }

$Args = @(
    "-m", $ModelPath,
    "--jinja",
    "--host", $HostAddr,
    "--port", $Port,
    "-t", $Threads,
    "-c", $Context,
    "-n", "32768",
    "-np", "1",
    "--no-mmproj",
    "--gpu-layers-draft", "all",
    "--spec-type", "draft-mtp",
    "--spec-draft-n-max", $DraftMax,
    "--n-gpu-layers", "all",
    "--fit", "off",
    "--load-mode", "none",
    "--no-warmup",
    "--flash-attn", "on",
    "--cache-type-k", "q4_0",
    "--cache-type-v", "q4_0",
    "--batch-size", "512",
    "--ubatch-size", "512",
    "--temp", "1",
    "--top-p", "0.95",
    "--top-k", "20",
    "--min-p", "0.0",
    "--presence-penalty", "0.0",
    "--repeat-penalty", "1.0",
    "--reasoning", "auto",
    "--reasoning-preserve"
)

Write-Host "Starting llama-server (Qwen3.8-27B UD-IQ3_XXS + MTP)..."
Write-Host "  Build:    llama.cpp b10437 (CUDA 12.4)"
Write-Host "  Target:   Qwen3.8-27B-UD-IQ3_XXS (11.9GB, all GPU)"
Write-Host "  Spec:     draft-mtp draft-max=$DraftMax (set LLAMA_DRAFT_MAX=1 for tool-call safety)"
Write-Host "  Context:  $Context"
Write-Host "  KV cache: q4_0/q4_0"
Write-Host "  Reasoning: auto, effort=medium (preserve-thinking on)"
Write-Host "  Expected: ~50-55 t/s (per HF discussion #26 on same GPU)"
Write-Host ""

# Embedded-quote args break under PowerShell 5.1 native arg passing;
# env var form is the reliable route on Windows
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"preserve-thinking":true,"reasoning_effort":"medium"}'

# llama-server logs to stderr; with Stop preference the first log line would
# terminate the script as a NativeCommandError
$ErrorActionPreference = "Continue"

& $ServerExe @Args
