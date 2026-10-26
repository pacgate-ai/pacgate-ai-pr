# Benchmark — memory prompt prefix stability after `86a9feb`

**Date:** 2026-10-26
**Stack:** live `deer-flow` container, image `ghcr.io/jzkk720/deer-flow-pacgate:0.2.6`
**Change:** upstream `86a9feb` — `patches/deer-flow-memory-prompt.py` (bind-mounted, **no image rebuild**)
**Measured on:** this AIPC1 box, via the container's own Python and the live mounted module.

---

## 1. What was measured, and what was NOT

**Measured:** the shared-prefix length of `MEMORY_UPDATE_PROMPT` when the
conversation is held constant and only `current_memory` changes. This is the
mechanism the commit targets — llama.cpp reuses a KV prefix only up to the first
differing token, so the share of the prompt that stays constant *is* the
reusable fraction.

**NOT measured:** wall-clock prefill seconds. Upstream reports 68.7 s → 1.3 s on
their HX370 box (Ollama 0.40.11, gemma4:12b-it-qat). I did not reproduce those
numbers here: a faithful re-run needs a controlled sequence of live memory
updates on a fixed conversation, and this box's Ollama log rotates past the
window fast enough that a stale measurement cannot be attributed to this change.
Reporting 68.7 → 1.3 s from here would be repeating someone else's number as if
it were mine.

---

## 2. Live-state verification

```
order_conversation_first True
cap_chars              16000
cap_msgs                40
bounded                True  (len 16005 for an 80-message conversation)
```

Live file check:

```
cap16000=1        # MEMORY_CONVERSATION_MAX_CHARS = 16000
cap40=1           # MEMORY_CONVERSATION_MAX_MESSAGES = 40
line 44: {conversation}
line 49: {current_memory}
```

`{conversation}` now precedes `{current_memory}` — the conversation block is
append-only within a thread, so the prefix is stable.

This matches upstream's own reported state (`cap: 16000 | conversation first:
True`), independently reproduced on this machine.

---

## 3. The number that matters — old vs new, same conversation

Method: a ~16 000-char research conversation held **constant**; two different
`current_memory` payloads rendered through the same template. Shared-prefix
length is the longest common prefix.

| | Old order (memory block first) | New order (`86a9feb`) |
|---|---|---|
| Total prompt | 22 630 chars | 22 630 chars |
| Shared prefix across a memory change | **218 chars** | **16 278 chars** |
| Shared share | **1.0 %** | **71.9 %** |
| Reusable prefix gain | — | **+16 060 chars** |

And when memory is **unchanged**, the rendered prompt is byte-identical
(`identical_when_memory_unchanged True`) — so a repeat update hits the same
prefix regardless of ordering.

### Reading of the result

Under the old order, **99 % of the prompt changed identity on every update** —
the volatile memory block sat in front, so the cache diverged within the first
~200 characters and the entire 22.6 k-token prefill was paid again. Under the new
order, ~72 % of the prompt is a stable prefix, and only the trailing memory block
differs. That is the difference between "no cache reuse, ever" and "reuse most of
it", which is exactly the shape of the 68.7 s → 1.3 s upstream reports.

The remaining 28 % that is not shared is the memory block itself plus the closing
instructions after it — unavoidable, since the model must read the updated
memory.

---

## 4. Input bound

`format_conversation_for_update` on an 80-message conversation of 990-char
turns returns **16 005 chars** — capped at `MEMORY_CONVERSATION_MAX_CHARS =
16000` (+ the 5-char `"...\n\n"` elision marker), keeping the **newest** turns.
Before the change the same input was unbounded and reached chat size, which paid
the cold prefill *and* evicted the chat lane's prompt-cache entry from the same
8 GiB budget.

---

## 5. Nothing else moved

- **No image rebuild.** All five release services still run
  `ghcr.io/jzkk720/*:0.2.6`; `test-stack-version-coherence.ps1` passes 14/14.
- **No tag pushed.** The GHCR workflow triggers on `v0.1.*`/`v0.2.*`, so it
  correctly did not fire.
- **Lane still sanitized** (the red line): `PACGATE_MATTER_ID` is set, the
  storage patch still carries `REFUSING to fall back`, and our identifier
  redaction is present in the mounted updater patch.
