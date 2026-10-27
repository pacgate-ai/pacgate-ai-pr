# Benchmark — windowed loop guard after adopting `86a9feb..44f7f43`

**Date:** 2026-10-27
**Stack:** live `deer-flow`, image `ghcr.io/jzkk720/deer-flow-pacgate:0.2.6` (unchanged)
**Change:** `patches/deer-flow-loop-detection.py` (bind-mounted) + `loop_detection:` config block

---

## 1. The defect, measured on this box before the change

```
2026-10-27 01:46:34  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 01:54:07  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 02:03:00  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 02:12:44  WARNING  Tool frequency warning — too many calls to same tool type
2026-10-27 02:15:00  ERROR    Tool frequency hard limit reached — forcing stop
```

Root cause read from the live file, not inferred: line 226 was
`self._tool_freq: dict[str, dict[str, int]]` — a monotonic integer per
`(thread_id, tool_name)`, cleared only by `reset()` (lines 601–610), which the
gateway never calls. Every `bash` call for a thread's whole life summed against
one ceiling of 50.

---

## 2. After the change — configured path

Measured by building the middleware the way the gateway does
(`LoopDetectionMiddleware.from_config(cfg.loop_detection)`), **not** with a
no-arg constructor:

```
CONFIG_PRESENT=True
CONFIG_WARN=50
CONFIG_HARD=75
CONFIG_OVERRIDES={'bash': (100, 150)}

BUILT_WINDOW=150      <- auto-sized to the largest hard limit (the bash override)
BUILT_WARN=50
BUILT_HARD=75
BUILT_BASH=(100, 150)
```

`BUILT_WINDOW=150` is the load-bearing number. The middleware sizes its window to
`max(window_size, hard_limit, every override hard_limit)`, so the bash override of
150 is what lifts the window from 50 to 150. That is why **both halves are
required**: the patch alone, with the default ceiling of 50, would have produced a
window of 50 — and the measured bash-heaviest run already packs 48 bash calls into
50.

---

## 3. Live state

```
windowed middleware markers (_tool_name_counter) = 5
old monotonic line (self._tool_freq: dict)       = 0
config ceiling present in /app/backend/config.yaml = yes
force-stops since the recreate                    = 0
```

The gate `test-loop-detection-window.ps1` reports **33 passed, 0 failed** — the
same 33/33 upstream claimed, now reproducible here.

---

## 4. What was NOT measured

The 92-call productive replay (71 bash / 55 distinct commands) was **not** re-run
end-to-end. That needs a live document-assembly run of that shape, which this
audit did not perform. The claim therefore rests on:

- the window arithmetic above (150 slots vs a measured peak of 74 bash in 150), and
- the absence of any new force-stop since the rollout.

It does **not** rest on a reproduced 92-call run. Stating that plainly rather than
borrowing upstream's number.

---

## 5. Nothing else moved

- **No image rebuild.** All five release images still `0.2.6`.
- **Red line intact.** `PACGATE_MATTER_ID` set; storage patch still carries
  `REFUSING to fall back`; the `86a9feb` memory-prompt cap still live.
- **MCP connectors intact.** 30 servers; the extensions render did not fire
  (no `install.ps1` run). Backup:
  `deer-flow-extensions-config.json.bak.pre-loopguard-20261027-193229`.
