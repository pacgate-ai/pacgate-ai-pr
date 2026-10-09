# 2026-10-09 — ctx/summarization root cause + fix (verified live)

## Symptoms reported
1. Cloud model "very lag / hung" generating documents
2. Local model GPU never above ~40% compute (dGPU RX 7600 XT 16GB)

## Root cause A — summarization trigger structurally unreachable (FIXED)
- `SummarizationMiddleware` trigger counts **message tokens only**
  (`count_tokens_approximately` over the message list ≈ 16k for 50 msgs).
- Real per-call input = **83k** (≈32k tools+system + ~16k messages + cloud
  overhead). The 48k message-token threshold could never be reached by the
  counter → summarization NEVER fired → every call re-sent 83k.
- Cloud doc runs: 20+ calls × 83k = 1.3–1.7M tokens, 60–120s per call = the "lag".
- The reported-tokens fallback (`_should_summarize_based_on_reported_tokens`)
  checks ONLY the **last** AI message usage ≥ threshold AND
  `response_metadata.model_provider == ls_provider` ("openai"=="openai" ✓).
  It works but is fragile: any AI msg with usage < threshold resets it.

## Fix applied (config-only, verified live 03:38–03:46)
- `pacgate-ai/deploy/client-bundle/deer-flow-config.yaml`:
  `summarization.trigger: tokens 48000 → 12000` (keep=12000 unchanged).
- Verified live with instrumented hook: `should=True` → summary call executed →
  state rewritten to `[summary-human, ...preserved]` → next model call
  **input=32770 (bounded)** vs 83k before. ~60% input reduction per call.
- Instrumentation (SUMM-DEBUG log lines) added then REMOVED; middleware file clean.

## Debug methodology that worked (reuse)
- Middleware IS in the compiled graph: `agent.nodes["DeerFlowSummarizationMiddleware.before_model"]`,
  edges `tools → summarization → model` confirmed via `agent.get_graph().edges`.
- The live middleware instance: `node.bound.func.__self__` — test `_should_summarize`
  against real checkpoint state directly.
- Live instrumentation: patch the baked-in file inside the container
  (`/app/backend/packages/harness/deerflow/agents/middlewares/summarization_middleware.py`),
  `docker compose restart deer-flow`, run a real API run, read logs. Revert after.
- API auth for test runs: registration is disabled; create a user in-process:
  `init_engine_from_config(cfg.database)` then `get_local_provider().create_user(...)`.
  Login via `POST /api/v1/auth/login/local` form-encoded (NO Origin header —
  Origin triggers CSRF cross-site rejection). Session cookie + csrf_token cookie;
  POSTs need `X-CSRF-Token` header = csrf cookie value.
- To test a big-history thread without the owner: copy rows in
  `checkpoints.db` (checkpoints + writes) to a NEW thread_id (reusing an
  existing thread id gets shadowed by newer checkpoint_ids), copy the
  `threads_meta` row, then reassign `user_id` to the test user.

## Root cause B — GPU ~40% ceiling = HARDWARE limit (not fixed; user decision)
- `ollama ps`: nemotron-3.5-lightning:30b-a3b = **25GB, 46%/54% CPU/GPU split**
  on the 16GB RX 7600 XT. GPU compute engine 15–51%, **copy engine 27–39%**
  (PCIe shuffle for CPU-resident layers). The GPU waits on CPU matmuls + PCIe.
- This is inherent to a 25GB model on 16GB VRAM. Not a config bug.
- Options (need user decision, per memory rule):
  a. Keep as-is (30B-class capability, 1M ctx, accept ~40% GPU + 200 t/s prefill).
  b. Switch default to gemma4:12b-it-qat (7.2GB, 100% GPU, 580 t/s prefill,
     23s wall in 10-08 bench) — 3x faster prefill for doc generation, but 12B-class.
  c. Pull a q4 quant of nemotron-30b (~13GB → fits) if it exists.
- KV/keep-alive env (q8_0, 10m) already applied 10-08 — working.

## Also observed
- Container restarted 01:18 (gateway "restarted before durable final state"
  error on run 22b49cc8) — cause not investigated; runs recovered as orphaned.
- 141 MCP tools cached (was 137) — tool schema overhead ~19.5k tokens
  (measured: fresh-thread input 32770 − 13.2k messages ≈ 19.5k tools+system).
- Test artifacts cleaned: test user deleted, copied threads/checkpoints removed,
  real thread ownership restored to admin.
