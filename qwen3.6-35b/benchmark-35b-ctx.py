"""
35B MoE Context-Scaling Benchmark

Tests generation speed at different -c (context) values to find
the sweet spot where context room meets the ~40 t/s target.

How it works:
  1. Stops current llama-server
  2. Restarts with -c <value> (64K, 80K, 100K, 120K)
  3. Measures generation speed with short AND long prompts
  4. Records VRAM usage
  5. Moves to next context size

Usage:
  python benchmark-35b-ctx.py              # Run full test sequence
  python benchmark-35b-ctx.py --quick      # Quick test (short prompts only)
  python benchmark-35b-ctx.py --compare    # Compare saved results
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

# â•â•â• Configuration â•â•â•
SERVER_URL = os.environ.get("LLAMA_BENCH_URL", "http://127.0.0.1:8080/v1/chat/completions")
SCRIPT_DIR = Path(__file__).parent.parent.parent
SERVER_EXE = SCRIPT_DIR / "llama.cpp-b9360-cuda12" / "llama-server.exe"
MODEL_PATH = SCRIPT_DIR / "models" / "Qwen3.6-35B-A3B-MTP-GGUF" / "Qwen3.6-35B-A3B-UD-Q4_K_S.gguf"
RESULTS_DIR = SCRIPT_DIR / "benchmark_results"

CONTEXT_SIZES = [64000, 80000, 100000, 120000]

# Common server flags (from start-server-35b.ps1 production config)
COMMON_FLAGS = [
    "--jinja",
    "--host", "127.0.0.1",
    "--port", "8080",
    "-t", "16",
    "-n", "32768",
    "-np", "1",
    "-fa", "on",
    "--fit", "on",
    "--kv-unified",
    "--no-mmproj",
    "-ctk", "q8_0",
    "-ctv", "q8_0",
    "--spec-type", "draft-mtp,ngram-mod",
    "--spec-draft-n-max", "2",
    "--spec-ngram-mod-n-match", "40",
    "--spec-ngram-mod-n-min", "0",
    "--spec-ngram-mod-n-max", "16",
    "-rea", "off",
]

# Test prompts: short (baseline speed) and long (simulates KV cache pressure)
SHORT_PROMPT = "Write a Python function that checks if a number is prime. Return only the function."
LONG_PROMPT_500 = """Write a detailed analysis of the following programming paradigms:
1. Object-Oriented Programming - history, key concepts, examples
2. Functional Programming - history, key concepts, examples
3. Logic Programming - history, key concepts, examples
4. Procedural Programming - history, key concepts, examples
5. Event-Driven Programming - history, key concepts, examples

For each paradigm, include:
- Origin decade and key contributors
- Core principles (at least 3)
- Primary languages associated with it
- A short code example illustrating the paradigm
- Strengths and weaknesses

Be thorough and detailed. Write at least 200 words per paradigm."""

LONG_PROMPT_1K = """You are a senior software architect. Provide a comprehensive technical design document for a distributed task queue system. Include:

## 1. System Overview
Describe the architecture, components, and data flow.

## 2. API Design
Define REST endpoints for:
- Task submission (with priority, delay, retry config)
- Task status query
- Task cancellation
- Queue management (list, purge, pause)
- Worker registration and heartbeat

## 3. Data Model
Define schemas for: Task, Queue, Worker, RetryPolicy, DeadLetterEntry

## 4. Reliability
- At-least-once delivery guarantee
- Idempotent task execution
- Dead letter queue handling
- Crash recovery procedure

## 5. Scaling
- Horizontal scaling strategy for workers
- Queue partitioning approach
- Load balancing between workers
- Handling backpressure

## 6. Monitoring
- Key metrics to track
- Alerting thresholds
- Dashboard design

## 7. Security
- Authentication model
- Authorization (RBAC)
- Encryption at rest and in transit

Be extremely detailed. Write production-grade specifications."""


def stop_server():
    """Kill any running llama-server."""
    print("  Stopping existing server...")
    try:
        subprocess.run(
            ["taskkill", "/F", "/IM", "llama-server.exe"],
            capture_output=True, timeout=10
        )
        time.sleep(3)
        # Verify it's gone
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq llama-server.exe"],
            capture_output=True, text=True, timeout=5
        )
        if "llama-server.exe" in result.stdout:
            print("  WARNING: Server still running, forcing harder...")
            subprocess.run(
                ["taskkill", "/F", "/IM", "llama-server.exe"],
                capture_output=True, timeout=10
            )
            time.sleep(3)
    except Exception as e:
        print(f"  Stop error (ok if not running): {e}")


def start_server(context_size):
    """Start llama-server with given context size."""
    cmd = [
        str(SERVER_EXE),
        "-m", str(MODEL_PATH),
        "-c", str(context_size),
    ] + COMMON_FLAGS

    print(f"  Starting server with -c {context_size}...")
    # Start in background, redirect output to log
    log_path = SCRIPT_DIR / f"ctx-bench-{context_size}.log"
    with open(log_path, "w") as log_file:
        proc = subprocess.Popen(
            cmd,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0,
        )
    return proc, log_path


def wait_for_server(timeout=120):
    """Wait until server responds to health check."""
    print("  Waiting for server...", end="", flush=True)
    started = time.time()
    while time.time() - started < timeout:
        try:
            req = urllib.request.Request("http://127.0.0.1:8080/health")
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    print(f" ready ({time.time()-started:.1f}s)")
                    return True
        except Exception:
            pass
        print(".", end="", flush=True)
        time.sleep(2)
    print(f" FAILED after {timeout}s")
    return False


def get_vram_usage():
    """Get GPU VRAM usage via nvidia-smi."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.used,memory.free,memory.total",
             "--format=csv,noheader"],
            capture_output=True, text=True, timeout=10
        )
        parts = result.stdout.strip().split(",")
        if len(parts) == 3:
            return {
                "used_mib": int(parts[0].strip().split()[0]),
                "free_mib": int(parts[1].strip().split()[0]),
                "total_mib": int(parts[2].strip().split()[0]),
            }
    except Exception as e:
        print(f"  VRAM check failed: {e}")
    return None


def get_server_props():
    """Get server properties (n_ctx, model info)."""
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/props")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read())
    except Exception:
        return None


def call_model(prompt, max_tokens=300, temperature=0.6):
    """Call model and return speed metrics."""
    payload = {
        "model": "local",
        "messages": [
            {"role": "system", "content": "You are a helpful assistant. Be concise but thorough."},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
        "top_p": 0.95,
        "top_k": 20,
        "min_p": 0.05,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        SERVER_URL, data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    started = time.perf_counter()
    with urllib.request.urlopen(req, timeout=300) as resp:
        body = resp.read().decode("utf-8")
    elapsed = time.perf_counter() - started

    parsed = json.loads(body)
    usage = parsed.get("usage", {})
    timings = parsed.get("timings", {})

    pt = usage.get("prompt_tokens", 0)
    ct = usage.get("completion_tokens", 0)

    # Server-reported generation speed (the accurate one)
    tps_server = timings.get("predicted_per_second")
    # Prompt processing speed
    tps_prompt = timings.get("prompt_per_second")
    # Time to first token
    ttft_ms = timings.get("prompt_ms", 0)
    # Generation time
    gen_ms = timings.get("predicted_ms", 0)

    return {
        "prompt_tokens": pt,
        "completion_tokens": ct,
        "total_tokens": pt + ct,
        "elapsed_sec": round(elapsed, 2),
        "gen_tps_server": round(tps_server, 2) if tps_server else None,
        "prompt_tps": round(tps_prompt, 2) if tps_prompt else None,
        "ttft_ms": round(ttft_ms, 1),
        "gen_ms": round(gen_ms, 1),
        "gen_tps_corrected": round(ct / (gen_ms / 1000), 2) if gen_ms > 0 and ct > 0 else None,
    }


def run_context_test(ctx_size, quick=False):
    """Run benchmark for a single context size."""
    print(f"\n{'='*60}")
    print(f"  Context Size: {ctx_size}")
    print(f"{'='*60}")

    # Stop existing server
    stop_server()

    # Start with new context size
    proc, log_path = start_server(ctx_size)

    # Wait for server
    if not wait_for_server():
        print(f"  FAILED: Server didn't start at -c {ctx_size}")
        stop_server()
        return None

    # Let server settle
    time.sleep(2)

    # Check VRAM
    vram = get_vram_usage()
    if vram:
        print(f"  VRAM: {vram['used_mib']}/{vram['total_mib']} MiB ({vram['free_mib']} free)")

    # Verify context size
    props = get_server_props()
    n_ctx = props.get("default_generation_settings", {}).get("params", {}).get("n_ctx", "?") if props else "?"
    print(f"  Server n_ctx: {n_ctx}")

    results = {
        "context_size": ctx_size,
        "server_n_ctx": n_ctx,
        "vram": vram,
        "timestamp": datetime.now().isoformat(),
        "tests": [],
    }

    # Test 1: Short prompt (baseline - minimal KV cache)
    print("\n  Test 1: Short prompt (baseline)...")
    try:
        r = call_model(SHORT_PROMPT, max_tokens=200)
        results["tests"].append({"name": "short_baseline", **r})
        print(f"    Gen t/s: {r['gen_tps_server']} (server) | {r['gen_tps_corrected']} (corrected)")
        print(f"    Tokens: {r['prompt_tokens']}p + {r['completion_tokens']}c")
        print(f"    TTFT: {r['ttft_ms']}ms | Gen: {r['gen_ms']}ms")
    except Exception as e:
        print(f"    ERROR: {e}")
        results["tests"].append({"name": "short_baseline", "error": str(e)})

    # Test 2: Medium prompt (~500 tokens context)
    print("\n  Test 2: Medium prompt (~500 tok context)...")
    try:
        r = call_model(LONG_PROMPT_500, max_tokens=400)
        results["tests"].append({"name": "medium_500tok", **r})
        print(f"    Gen t/s: {r['gen_tps_server']} (server) | {r['gen_tps_corrected']} (corrected)")
        print(f"    Tokens: {r['prompt_tokens']}p + {r['completion_tokens']}c")
        print(f"    TTFT: {r['ttft_ms']}ms | Gen: {r['gen_ms']}ms")
    except Exception as e:
        print(f"    ERROR: {e}")
        results["tests"].append({"name": "medium_500tok", "error": str(e)})

    if not quick:
        # Test 3: Long prompt (~1K tokens context)
        print("\n  Test 3: Long prompt (~1K tok context)...")
        try:
            r = call_model(LONG_PROMPT_1K, max_tokens=500)
            results["tests"].append({"name": "long_1ktok", **r})
            print(f"    Gen t/s: {r['gen_tps_server']} (server) | {r['gen_tps_corrected']} (corrected)")
            print(f"    Tokens: {r['prompt_tokens']}p + {r['completion_tokens']}c")
            print(f"    TTFT: {r['ttft_ms']}ms | Gen: {r['gen_ms']}ms")
        except Exception as e:
            print(f"    ERROR: {e}")
            results["tests"].append({"name": "long_1ktok", "error": str(e)})

        # Test 4: Multi-turn (simulates growing KV cache)
        print("\n  Test 4: Multi-turn (5 turns, growing context)...")
        multi_turn_speeds = []
        messages = [{"role": "system", "content": "You are a helpful assistant."}]
        for i in range(5):
            messages.append({"role": "user", "content": f"Explain concept {i+1}: {['recursion', 'memoization', 'dynamic programming', 'graph traversal', 'binary search'][i]}. Be detailed."})
            payload = {
                "model": "local",
                "messages": messages,
                "max_tokens": 150,
                "temperature": 0.6,
                "top_p": 0.95,
                "top_k": 20,
                "stream": False,
                "chat_template_kwargs": {"enable_thinking": False},
            }
            try:
                data = json.dumps(payload).encode("utf-8")
                req = urllib.request.Request(SERVER_URL, data=data,
                    headers={"Content-Type": "application/json"}, method="POST")
                with urllib.request.urlopen(req, timeout=120) as resp:
                    body = resp.read().decode("utf-8")
                parsed = json.loads(body)
                ct = parsed.get("usage", {}).get("completion_tokens", 0)
                pt = parsed.get("usage", {}).get("prompt_tokens", 0)
                tps = parsed.get("timings", {}).get("predicted_per_second")
                assistant_msg = parsed["choices"][0]["message"]["content"]
                messages.append({"role": "assistant", "content": assistant_msg})
                multi_turn_speeds.append({"turn": i+1, "prompt_tokens": pt, "gen_tps": round(tps, 2) if tps else None})
                print(f"    Turn {i+1}: {tps:.1f} t/s | {pt}p tok")
            except Exception as e:
                print(f"    Turn {i+1} ERROR: {e}")
                multi_turn_speeds.append({"turn": i+1, "error": str(e)})

        results["tests"].append({"name": "multi_turn", "turns": multi_turn_speeds})

    # Stop server after test
    stop_server()

    # Save individual result
    RESULTS_DIR.mkdir(exist_ok=True)
    out_path = RESULTS_DIR / f"35b_ctx_{ctx_size}.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"\n  Saved: {out_path}")

    return results


def run_full_benchmark(quick=False):
    """Run benchmarks across all context sizes."""
    all_results = []

    for ctx in CONTEXT_SIZES:
        result = run_context_test(ctx, quick=quick)
        if result:
            all_results.append(result)
        time.sleep(2)  # Brief pause between tests

    # Summary
    print(f"\n{'='*70}")
    print(f"  CONTEXT SCALING SUMMARY â€” 35B MoE (Q4_K_S + MTP+ngram)")
    print(f"{'='*70}")
    print(f"  {'Context':>8} | {'Short t/s':>10} | {'Medium t/s':>10} | {'VRAM used':>10}")
    print(f"  {'-'*8}-+-{'-'*10}-+-{'-'*10}-+-{'-'*10}")

    for r in all_results:
        ctx = r["context_size"]
        short_tps = next((t.get("gen_tps_server") for t in r["tests"] if t.get("name") == "short_baseline"), "?")
        med_tps = next((t.get("gen_tps_server") for t in r["tests"] if t.get("name") == "medium_500tok"), "?")
        vram = r.get("vram", {})
        vram_str = f"{vram.get('used_mib', '?')} MiB" if vram else "?"
        print(f"  {ctx:>8} | {str(short_tps):>10} | {str(med_tps):>10} | {vram_str:>10}")

    # Save combined results
    combined_path = RESULTS_DIR / "35b_ctx_scaling_summary.json"
    with open(combined_path, "w", encoding="utf-8") as f:
        json.dump({
            "model": "35B MoE Q4_K_S + MTP+ngram",
            "timestamp": datetime.now().isoformat(),
            "context_sizes_tested": CONTEXT_SIZES,
            "results": all_results,
        }, f, indent=2)
    print(f"\n  Full results: {combined_path}")

    # Recommendation
    print(f"\n  RECOMMENDATION:")
    target_tps = 40
    best_ctx = None
    for r in all_results:
        tps = next((t.get("gen_tps_server") for t in r["tests"] if t.get("name") == "short_baseline"), 0)
        if tps and tps >= target_tps:
            best_ctx = r["context_size"]
    if best_ctx:
        print(f"  Highest context at >= {target_tps} t/s: {best_ctx}")
    else:
        closest = min(all_results, key=lambda r: abs(
            (next((t.get("gen_tps_server", 999) for t in r["tests"] if t.get("name") == "short_baseline"), 999)) - target_tps
        ))
        print(f"  No context size reached {target_tps} t/s. Closest: {closest['context_size']}")

    return all_results


def compare_results():
    """Compare all saved context-scaling results."""
    RESULTS_DIR.mkdir(exist_ok=True)
    files = sorted(RESULTS_DIR.glob("35b_ctx_*.json"))
    if not files:
        print("No context-scaling results found.")
        return

    print(f"{'Context':>8} | {'Short t/s':>10} | {'Medium t/s':>10} | {'Long t/s':>10} | {'Multi-turn avg':>14} | {'VRAM':>10}")
    print("-" * 80)

    for f in files:
        with open(f, encoding="utf-8") as fh:
            data = json.load(fh)

        ctx = data.get("context_size", "?")
        vram = data.get("vram", {})
        vram_str = f"{vram.get('used_mib', '?')}/{vram.get('total_mib', '?')}" if vram else "?"

        short = next((t.get("gen_tps_server", "?") for t in data.get("tests", []) if t.get("name") == "short_baseline"), "?")
        med = next((t.get("gen_tps_server", "?") for t in data.get("tests", []) if t.get("name") == "medium_500tok"), "?")
        long = next((t.get("gen_tps_server", "?") for t in data.get("tests", []) if t.get("name") == "long_1ktok"), "?")

        mt_test = next((t for t in data.get("tests", []) if t.get("name") == "multi_turn"), None)
        if mt_test and "turns" in mt_test:
            speeds = [t.get("gen_tps") for t in mt_test["turns"] if t.get("gen_tps")]
            mt_avg = round(sum(speeds) / len(speeds), 1) if speeds else "?"
        else:
            mt_avg = "?"

        print(f"{ctx:>8} | {str(short):>10} | {str(med):>10} | {str(long):>10} | {str(mt_avg):>14} | {vram_str:>10}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="35B MoE Context-Scaling Benchmark")
    parser.add_argument("--quick", action="store_true", help="Quick test (short+medium prompts only)")
    parser.add_argument("--compare", action="store_true", help="Compare saved results")
    parser.add_argument("--context", type=int, help="Test single context size only")
    args = parser.parse_args()

    if args.compare:
        compare_results()
        return 0

    # Verify files exist
    if not SERVER_EXE.exists():
        print(f"ERROR: Server not found: {SERVER_EXE}")
        return 1
    if not MODEL_PATH.exists():
        print(f"ERROR: Model not found: {MODEL_PATH}")
        return 1

    if args.context:
        run_context_test(args.context, quick=args.quick)
    else:
        run_full_benchmark(quick=args.quick)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
