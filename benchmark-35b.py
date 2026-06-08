"""
Qwen 3.6 35B MoE -- Benchmark Script

Run against whatever server is currently running (llama.cpp or ik_llama.cpp).
Results saved to benchmark_results/35b_<label>.json with runtime label.

Usage:
  1. Start server:  start-server-q4ks-vanilla.ps1       (llama.cpp baseline)
  2. Run bench:     python benchmark-35b.py --label llama-b9360-q4ks
  3. Start server:  start-server-ik-35b-moe-ncpumoe16.ps1 (ik_llama.cpp n-cpu-moe)
  4. Run bench:     python benchmark-35b.py --label ik-ncpumoe16
  5. Compare:       python benchmark-35b.py --compare
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import textwrap
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path


SERVER_URL = os.environ.get("LLAMA_BENCH_URL", "http://127.0.0.1:8080/v1/chat/completions")
TEMPERATURE = float(os.environ.get("LLAMA_BENCH_TEMPERATURE", "0.6"))
MAX_TOKENS = int(os.environ.get("LLAMA_BENCH_MAX_TOKENS", "700"))
TIMEOUT = int(os.environ.get("LLAMA_BENCH_TIMEOUT", "900"))
RESULTS_DIR = Path(__file__).parent / "benchmark_results"

# Qwen 3.6 recommended sampling: temp=0.6, top_p=0.95, top_k=20, min_p=0, presence_penalty=1.25
SAMPLING = {
    "temperature": TEMPERATURE,
    "top_p": 0.95,
    "top_k": 20,
    "min_p": 0.0,
    "presence_penalty": 1.25,
}

TASKS = [
    {
        "name": "lru_cache",
        "prompt": """
Write Python 3 code only.
Implement an `LRUCache` class with:
- `__init__(capacity: int)`
- `get(key: int) -> int`
- `put(key: int, value: int) -> None`

Requirements:
- `get` returns `-1` when missing.
- Both operations must be O(1).
- Use only the Python standard library.
- Do not include explanation or markdown fences.
""",
        "test_code": """
cache = LRUCache(2)
cache.put(1, 1)
cache.put(2, 2)
assert cache.get(1) == 1
cache.put(3, 3)
assert cache.get(2) == -1
cache.put(4, 4)
assert cache.get(1) == -1
assert cache.get(3) == 3
assert cache.get(4) == 4
""",
    },
    {
        "name": "topological_sort",
        "prompt": """
Write Python 3 code only.
Implement a function:

`def topo_sort(num_nodes: int, edges: list[tuple[int, int]]) -> list[int]:`

The graph is directed with nodes `0..num_nodes-1`.
Return a valid topological ordering.
Raise `ValueError("cycle")` if the graph contains a cycle.
Use only the Python standard library.
Do not include explanation or markdown fences.
""",
        "test_code": """
order = topo_sort(6, [(5, 2), (5, 0), (4, 0), (4, 1), (2, 3), (3, 1)])
assert sorted(order) == [0, 1, 2, 3, 4, 5]
pos = {node: idx for idx, node in enumerate(order)}
for src, dst in [(5, 2), (5, 0), (4, 0), (4, 1), (2, 3), (3, 1)]:
    assert pos[src] < pos[dst]
try:
    topo_sort(3, [(0, 1), (1, 2), (2, 0)])
    raise AssertionError("Expected cycle")
except ValueError as exc:
    assert str(exc) == "cycle"
""",
    },
    {
        "name": "word_break_paths",
        "prompt": """
Write Python 3 code only.
Implement:

`def all_segmentations(s: str, words: set[str]) -> list[str]:`

Return every possible sentence formed by inserting spaces into `s` so that every token is in `words`.
Return the results sorted lexicographically.
Use memoization so repeated suffix work is avoided.
Use only the Python standard library.
Do not include explanation or markdown fences.
""",
        "test_code": """
result = all_segmentations("catsanddog", {"cat", "cats", "and", "sand", "dog"})
assert result == ["cat sand dog", "cats and dog"]
result = all_segmentations("pineapplepenapple", {"apple", "pen", "applepen", "pine", "pineapple"})
assert result == [
    "pine apple pen apple",
    "pine applepen apple",
    "pineapple pen apple",
]
assert all_segmentations("catsandog", {"cats", "dog", "sand", "and", "cat"}) == []
""",
    },
    {
        "name": "merge_intervals",
        "prompt": """
Write Python 3 code only.
Implement:

`def merge_intervals(intervals: list[list[int]]) -> list[list[int]]:`

Given a list of [start, end] intervals (inclusive), merge all overlapping intervals
and return the result sorted by start. Empty input returns empty list.
Use only the Python standard library.
Do not include explanation or markdown fences.
""",
        "test_code": """
assert merge_intervals([]) == []
assert merge_intervals([[1, 3]]) == [[1, 3]]
assert merge_intervals([[1, 3], [2, 6], [8, 10], [15, 18]]) == [[1, 6], [8, 10], [15, 18]]
assert merge_intervals([[1, 4], [4, 5]]) == [[1, 5]]
assert merge_intervals([[1, 4], [0, 4]]) == [[0, 4]]
assert merge_intervals([[1, 4], [2, 3]]) == [[1, 4]]
""",
    },
    {
        "name": "bank_simulation",
        "prompt": """
Write Python 3 code only.
Implement:

`class Bank:`
- `__init__(self)`
- `deposit(self, account: str, amount: float) -> None`
- `withdraw(self, account: str, amount: float) -> bool`
- `get_balance(self, account: str) -> float`
- `transfer(self, from_acc: str, to_acc: str, amount: float) -> bool`

Rules:
- withdraw returns False if insufficient funds or account does not exist
- transfer returns False if withdrawal fails; must be atomic (both or neither)
- get_balance returns 0.0 for non-existent accounts
- deposit creates account if it does not exist
Use only the Python standard library.
Do not include explanation or markdown fences.
""",
        "test_code": """
b = Bank()
b.deposit("alice", 100.0)
assert b.get_balance("alice") == 100.0
assert b.withdraw("alice", 50.0) == True
assert b.get_balance("alice") == 50.0
assert b.withdraw("alice", 60.0) == False
assert b.get_balance("bob") == 0.0
b.deposit("bob", 200.0)
assert b.transfer("bob", "alice", 75.0) == True
assert b.get_balance("bob") == 125.0
assert b.get_balance("alice") == 125.0
assert b.transfer("bob", "alice", 200.0) == False
assert b.get_balance("bob") == 125.0
assert b.get_balance("alice") == 125.0
""",
    },
]


def extract_python_code(text: str) -> str:
    fenced = re.findall(r"```(?:python)?\s*(.*?)```", text, flags=re.DOTALL | re.IGNORECASE)
    if fenced:
        return fenced[0].strip()
    return text.strip()


def call_model(prompt: str) -> dict:
    payload = {
        "model": "Qwen3.6-35B-A3B",
        "messages": [
            {
                "role": "system",
                "content": "You are a careful Python programmer. Thinking mode is disabled. Return only valid Python code with no explanation.",
            },
            {"role": "user", "content": textwrap.dedent(prompt).strip()},
        ],
        "max_tokens": MAX_TOKENS,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
        **SAMPLING,
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        SERVER_URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    started = time.perf_counter()
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        body = resp.read().decode("utf-8")
    elapsed = time.perf_counter() - started

    parsed = json.loads(body)
    content = parsed["choices"][0]["message"]["content"]
    usage = parsed.get("usage", {})
    completion_tokens = usage.get("completion_tokens")
    prompt_tokens = usage.get("prompt_tokens")
    tps = None
    if completion_tokens and elapsed > 0:
        tps = completion_tokens / elapsed

    return {
        "raw": parsed,
        "content": content,
        "elapsed_sec": elapsed,
        "completion_tokens": completion_tokens,
        "prompt_tokens": prompt_tokens,
        "tokens_per_sec": tps,
    }


def run_python_tests(code: str, test_code: str) -> tuple[bool, str]:
    harness = (
        textwrap.dedent(code).strip()
        + "\n\n"
        + textwrap.dedent(test_code).strip()
        + '\nprint("TESTS_PASSED")\n'
    )

    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as handle:
        handle.write(harness)
        temp_path = handle.name

    try:
        proc = subprocess.run(
            [sys.executable, temp_path],
            capture_output=True,
            text=True,
            timeout=90,
        )
    finally:
        try:
            os.unlink(temp_path)
        except OSError:
            pass

    success = proc.returncode == 0 and "TESTS_PASSED" in proc.stdout
    output = (proc.stdout + "\n" + proc.stderr).strip()
    return success, output


def wait_for_server() -> None:
    print(f"Waiting for server: {SERVER_URL}")
    started = time.time()
    last_error = None
    while time.time() - started < 600:
        try:
            req = urllib.request.Request(
                SERVER_URL,
                data=json.dumps(
                    {
                        "model": "Qwen3.6-35B-A3B",
                        "messages": [{"role": "user", "content": "print(1)"}],
                        "temperature": 0,
                        "max_tokens": 1,
                        "stream": False,
                        "chat_template_kwargs": {"enable_thinking": False},
                    }
                ).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                if resp.status == 200:
                    return
        except Exception as exc:
            last_error = exc
            time.sleep(3)
    raise RuntimeError(f"Server did not become ready. Last error: {last_error}")


def run_benchmark(label: str) -> int:
    RESULTS_DIR.mkdir(exist_ok=True)
    wait_for_server()
    print("Server is ready.\n")

    results = []
    passed = 0
    all_tps = []

    for task in TASKS:
        print(f"=== {task['name']} ===")
        try:
            response = call_model(task["prompt"])
            code = extract_python_code(response["content"])
            ok, test_output = run_python_tests(code, task["test_code"])
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            results.append({"name": task["name"], "passed": False, "error": f"HTTP {exc.code}: {body}"})
            print(results[-1]["error"])
            print()
            continue
        except Exception as exc:
            results.append({"name": task["name"], "passed": False, "error": str(exc)})
            print(f"Error: {exc}\n")
            continue

        item = {
            "name": task["name"],
            "passed": ok,
            "elapsed_sec": round(response["elapsed_sec"], 2),
            "prompt_tokens": response["prompt_tokens"],
            "completion_tokens": response["completion_tokens"],
            "tokens_per_sec": round(response["tokens_per_sec"], 2) if response["tokens_per_sec"] else None,
            "code_preview": "\n".join(code.splitlines()[:20]),
            "test_output": test_output[-2000:],
        }
        results.append(item)

        if ok:
            passed += 1
        if item["tokens_per_sec"]:
            all_tps.append(item["tokens_per_sec"])

        print(f"  passed:   {ok}")
        print(f"  tok/s:    {item['tokens_per_sec']}")
        print(f"  tokens:   {item['completion_tokens']}")
        print(f"  elapsed:  {item['elapsed_sec']}s")
        if not ok:
            print(f"  test_output: {test_output[-500:]}")
        print()

    avg_tps = round(sum(all_tps) / len(all_tps), 2) if all_tps else None
    summary = {
        "model_size": "35B-MoE",
        "label": label,
        "timestamp": datetime.now().isoformat(),
        "server_url": SERVER_URL,
        "sampling": SAMPLING,
        "tasks_passed": passed,
        "tasks_total": len(TASKS),
        "average_tokens_per_sec": avg_tps,
        "results": results,
    }

    out_path = RESULTS_DIR / f"35b_{label}.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)

    print(f"=== 35B MoE Results [{label}] ===")
    print(f"  Passed:  {passed}/{len(TASKS)}")
    print(f"  Avg t/s: {avg_tps}")
    print(f"  Saved:   {out_path}")
    return 0 if passed == len(TASKS) else 1


def compare_results() -> None:
    RESULTS_DIR.mkdir(exist_ok=True)
    files = sorted(RESULTS_DIR.glob("35b_*.json"))
    if not files:
        print("No 35B benchmark results found in benchmark_results/")
        return

    print(f"{'Label':<30} {'Passed':>7} {'Avg t/s':>9} {'Date':>20}")
    print("-" * 70)
    for f in files:
        with open(f, encoding="utf-8") as fh:
            data = json.load(fh)
        label = data.get("label", f.stem)
        passed = f"{data.get('tasks_passed', '?')}/{data.get('tasks_total', '?')}"
        tps = data.get("average_tokens_per_sec", "-")
        ts = data.get("timestamp", "-")[:19]
        print(f"{label:<30} {passed:>7} {str(tps):>9} {ts:>20}")


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Qwen 3.6 35B MoE Benchmark")
    parser.add_argument("--label", default=None, help="Config label (e.g. llama-b9360-q4ks, ik-ncpumoe16)")
    parser.add_argument("--compare", action="store_true", help="Compare all saved 35B results")
    args = parser.parse_args()

    if args.compare:
        compare_results()
        return 0

    if not args.label:
        print("ERROR: --label is required (e.g. --label llama-b9360-q4ks)")
        print("Use --compare to see saved results.")
        return 1

    return run_benchmark(args.label)


if __name__ == "__main__":
    raise SystemExit(main())
