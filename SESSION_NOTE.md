We reset the setup to a clean state and verified the model in the smallest reliable way first.

What we did:
- killed all stale `llama-server` processes
- ensured only one server instance was running
- started the Qwen `UD-Q4_K_M` server on `127.0.0.1:8080`
- tested a single simple chat prompt instead of jumping into benchmarks

How we made it work:
- the server needed `chat_template_kwargs` at the top level of the OpenAI-style request
- specifically: `{"chat_template_kwargs":{"enable_thinking":false}}`
- without that, the model was putting text into `reasoning_content` and leaving `content` empty

Why this mattered:
- earlier results were invalid because two problems were mixed together:
  1. stale/orphan server processes
  2. wrong request shape for disabling thinking
- once both were fixed, the server returned a normal answer in `content`

Current known-good baseline:
- one server only
- plain chat works
- simple prompt returned `Four` for `2+2`
- ignore earlier noisy benchmark conclusions from the broken state
