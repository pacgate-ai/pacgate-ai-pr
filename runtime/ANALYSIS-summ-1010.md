# Summarization analysis (2026-10-10) — ROOT CAUSE CONFIRMED

## The smoking gun
Live instrumented logs show the summarization middleware IS firing and DOES
summarize (summary_len=33, 732, 1885). BUT the per-call INPUT tokens stay at
66-74k regardless:

| time | msgs | msg-tokens | summary_len | next call input |
|---|---|---|---|---|
| 02:31:25 | 5 | 5269 | 33 | 69051 |
| 02:33:20 | 12 | 5944 | 732 | 69865 |
| 02:34:08 | 15 | 10034 | 1885 | 73702 |

**Input = 64-66k CONSTANT overhead (tools+system) + messages.** Summarization
bounds the MESSAGE part (~5-10k) but the 64k tool/system overhead dominates.

## Why AIPC1 feels slow with cloud deepseek
1. **64k constant input per call** — 141 MCP tools + system prompt. Every single
   LLM call ships 64k tokens to ollama.com. At cloud latency this is 10-60s/call.
2. **cache_read=64200** — Ollama's prompt cache helps (64k cached), but the
   cloud round-trip still pays for the full payload upload each call.
3. **Summarization can't fix this** — it only trims messages, not the tool schema.
4. AIPC2 with nemotron LOCAL: no network round-trip, prefill at 580 t/s (gemma)
   or 30 t/s (nemotron), and the 64k prompt is processed locally.

## The real lever: reduce the bound tool surface
- 141 MCP tools ≈ 32k tokens of tool schemas (per 2026-10-09 finding: 32k tools+system).
- deer-flow has `deferred_tool_filter_middleware` + `tool_search` (assemble_deferred_tools)
  — tools can be deferred and loaded on demand.
- Config lever: `model_routing.tool_count_threshold` (currently 200) and the
  deferred-tools catalog.

## Fix options (config-only, no rebuild)
A. Enable deferred tools so only a small catalog is bound per call.
B. Trim the enabled MCP server list (18 enabled now; qcc/ansvar already off).
C. Accept: cloud is picker-only by design; local default is the fast path.

## Instrumentation state
- Patched summarization_middleware.py in-container with SUMM-DEBUG logs.
- REVERT after diagnosis (image rebuild also reverts). Patch file: runtime/patch-summ-1010.py
- The patch is EPHEMERAL (lost on container recreate).