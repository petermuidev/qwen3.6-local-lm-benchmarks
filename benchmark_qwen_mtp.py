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


SERVER_URL = os.environ.get("LLAMA_BENCH_URL", "http://127.0.0.1:8080/v1/chat/completions")
MODEL_NAME = os.environ.get("LLAMA_BENCH_MODEL", "Qwen3.6-35B-A3B-UD-Q4_K_M")
TEMPERATURE = float(os.environ.get("LLAMA_BENCH_TEMPERATURE", "0.2"))
MAX_TOKENS = int(os.environ.get("LLAMA_BENCH_MAX_TOKENS", "700"))
TIMEOUT = int(os.environ.get("LLAMA_BENCH_TIMEOUT", "900"))


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
]


def extract_python_code(text: str) -> str:
    fenced = re.findall(r"```(?:python)?\s*(.*?)```", text, flags=re.DOTALL | re.IGNORECASE)
    if fenced:
        return fenced[0].strip()
    return text.strip()


def call_model(prompt: str) -> dict:
    payload = {
        "model": MODEL_NAME,
        "messages": [
            {
                "role": "system",
                "content": "You are a careful Python programmer. Thinking mode is disabled. Return only valid Python code with no explanation.",
            },
            {
                "role": "user",
                "content": textwrap.dedent(prompt).strip(),
            },
        ],
        "temperature": TEMPERATURE,
        "max_tokens": MAX_TOKENS,
        "stream": False,
        "chat_template_kwargs": {
            "enable_thinking": False
        },
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
    started = time.time()
    last_error = None
    while time.time() - started < 600:
        try:
            req = urllib.request.Request(
                SERVER_URL,
                data=json.dumps(
                    {
                        "model": MODEL_NAME,
                        "messages": [{"role": "user", "content": "print(1)"}],
                        "temperature": 0,
                        "max_tokens": 1,
                        "stream": False,
                        "chat_template_kwargs": {
                            "enable_thinking": False
                        },
                    }
                ).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                if resp.status == 200:
                    return
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            time.sleep(3)
    raise RuntimeError(f"Server did not become ready. Last error: {last_error}")


def main() -> int:
    print(f"Waiting for server: {SERVER_URL}")
    wait_for_server()
    print("Server is ready.\n")

    results = []
    passed = 0

    for task in TASKS:
        print(f"=== {task['name']} ===")
        try:
            response = call_model(task["prompt"])
            code = extract_python_code(response["content"])
            ok, test_output = run_python_tests(code, task["test_code"])
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            results.append(
                {
                    "name": task["name"],
                    "passed": False,
                    "error": f"HTTP {exc.code}: {body}",
                }
            )
            print(results[-1]["error"])
            print()
            continue
        except Exception as exc:  # noqa: BLE001
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

        print(f"passed: {ok}")
        print(f"elapsed_sec: {item['elapsed_sec']}")
        print(f"completion_tokens: {item['completion_tokens']}")
        print(f"tokens_per_sec: {item['tokens_per_sec']}")
        if not ok:
            print("test_output:")
            print(item["test_output"])
        print()

    aggregate_tps = [
        result["tokens_per_sec"]
        for result in results
        if isinstance(result.get("tokens_per_sec"), (int, float))
    ]
    summary = {
        "server_url": SERVER_URL,
        "model": MODEL_NAME,
        "tasks_passed": passed,
        "tasks_total": len(TASKS),
        "average_tokens_per_sec": round(sum(aggregate_tps) / len(aggregate_tps), 2) if aggregate_tps else None,
        "results": results,
    }

    out_path = os.path.join(os.path.dirname(__file__), "benchmark_results.json")
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2)

    print("=== summary ===")
    print(json.dumps(summary, indent=2))
    print(f"\nSaved results to {out_path}")
    return 0 if passed == len(TASKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
