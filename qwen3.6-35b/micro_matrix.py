import json
import os
import sys
import time
import urllib.request


SERVER_URL = os.environ.get("LLAMA_BENCH_URL", "http://127.0.0.1:8080/v1/chat/completions")
MODEL_NAME = os.environ.get("LLAMA_BENCH_MODEL", "Qwen3.6-35B-A3B-UD-Q4_K_M")
THINKING = os.environ.get("LLAMA_TEST_THINKING", "off").lower()
PROMPT = os.environ.get(
    "LLAMA_TEST_PROMPT",
    "Explain recursion to a junior Python developer in exactly two short sentences.",
)
MAX_TOKENS = int(os.environ.get("LLAMA_TEST_MAX_TOKENS", "80"))


def post(payload: dict) -> dict:
    req = urllib.request.Request(
        SERVER_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=600) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    payload = {
        "model": MODEL_NAME,
        "messages": [{"role": "user", "content": PROMPT}],
        "temperature": 0,
        "max_tokens": MAX_TOKENS,
        "stream": False,
    }

    if THINKING == "off":
        payload["chat_template_kwargs"] = {"enable_thinking": False}

    started = time.perf_counter()
    response = post(payload)
    elapsed = time.perf_counter() - started

    message = response["choices"][0]["message"]
    timings = response.get("timings", {})
    result = {
        "thinking_mode": THINKING,
        "content": message.get("content"),
        "reasoning_content": message.get("reasoning_content"),
        "finish_reason": response["choices"][0].get("finish_reason"),
        "elapsed_sec": round(elapsed, 3),
        "prompt_ms": timings.get("prompt_ms"),
        "predicted_ms": timings.get("predicted_ms"),
        "predicted_per_second": timings.get("predicted_per_second"),
        "completion_tokens": response.get("usage", {}).get("completion_tokens"),
        "prompt_tokens": response.get("usage", {}).get("prompt_tokens"),
    }
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
