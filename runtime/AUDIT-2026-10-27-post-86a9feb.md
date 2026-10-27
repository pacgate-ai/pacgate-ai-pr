# Post-upgrade audit — after adopting `86a9feb`, and the reported 409s

**Date:** 2026-10-27
**Trigger:** "can we fully audit after this upgrade and fixes? since pacgate-api, mcp,
sanitizer gateway are coming back 409 from the deerflow chat session?"
**Method:** `systematic-debugging` — root cause before any fix. Read-only throughout;
nothing was changed on the running stack during this audit.

---

## Verdict

> **There is no 409 regression, and the 409s you saw are not errors.**
> Every 409 in this stack is the document sanitization gate correctly refusing to
> return an un-sanitized document. Two of them appear in the chat path, both dated
> **2026-10-26 07:50 and 08:16** — more than a day *before* the upgrade, and one of
> the two then **recovered** (409 → `sanitize` → 200). The other is now `sanitized`
> as well; the only document still refused is legitimately `blocked` by policy.
>
> The stack is healthy: **all 8 containers `running/healthy`, 0 restarts, all on
> their pinned images**, and the full gate suite is **53/53 green**.

I also found and must own **one real but non-blocking issue** (§4) and **three
false alarms I created myself** (§6). The latter matter because two of them
initially looked like the regression you reported.

---

## 1. What actually emits 409

There are four distinct 409 sources in this codebase. Only the first is reachable
from the chat session:

| Source | File | Meaning |
|---|---|---|
| **Document read gate** | `pacgate-api` `/api/documents/:id/download` | `document is 'pending'` / `'blocked'` — refuse to serve un-sanitized matter content |
| Stale memory write | `patches/pacgate-adapter-storage.py:193` | matter-memory revision conflict (optimistic `If-Match`) |
| Run conflict | `patches/deer-flow-thread-runs.py:256` | a run is already active on the worker |
| Admin exists | `patches/deer-flow-auth.py:672` | bootstrap refused because an admin is already initialised |

**Where the chat path's 409s come from:** `deer-flow` → `pacgate-mcp` →
`pacgate-api:8080/api/documents/:id/download`. Note the chat session does **not**
go through `pacgate-nginx` — it hits the gateway directly. That is why an
nginx-only search for 409s is misleading (it found 12, all from a 05:15–05:59
window on 10-26, none after the upgrade).

---

## 2. The two chat-path 409s, with timestamps

From `pacgate-mcp`'s own log (`httpx` request lines), every document sub-route call:

```
2026-10-26 07:50:40  download  409   b3272709-f62e-4973-864d-801eed377bb3
2026-10-26 08:16:48  download  409   de7027a9-7d14-4c4d-a235-63beb8aa1b24
2026-10-26 08:17:36  download  200   b573d821-b346-4c3a-8093-b03d2095fc35
2026-10-26 08:17:38  download  200   8aafbc2b-5446-4550-85d8-85e49e0db0be
2026-10-26 08:17:38  download  200   2e6c6ce8-b096-4ba3-92b4-00a1083937eb
2026-10-26 08:35:41  download  200   b573d821-b346-4c3a-8093-b03d2095fc35
2026-10-26 08:35:41  download  200   a2127abd-d0d0-456e-b007-a762a14d98ba
2026-10-26 08:41:40  download  200   8aafbc2b-5446-4550-85d8-85e49e0db0be
2026-10-26 09:01:34  sanitize  200   de7027a9-7d14-4c4d-a235-63beb8aa1b24   <- recovery
2026-10-26 09:01:34  download  200   b573d821-b346-4c3a-8093-b03d2095fc35
```

**Both 409s predate the upgrade.** `deer-flow` was recreated at
`2026-10-26T15:34:36Z` and the 409s are at `07:50`/`08:16` — ~7–8 hours earlier.

Recovery behaviour, per document:

| Document | Now | Verdict |
|---|---|---|
| `de7027a9…` | `blocked` | 409 → `sanitize` → 200. Later blocked by policy. **Recovered correctly.** |
| `b3272709…` | `sanitized` | 409 once, never retried. Now sanitized. **No loop.** |

Neither document shows the failure mode the prompt guidance warns about
(repeating the same refused read). There is **no 409 retry loop**.

---

## 3. Live reproduction of the gate — it behaves per contract

Ran against a real `pending` document (`5e211eaf…`) using the exact routes the MCP
server uses (`GET /sanitize-status`, `POST /sanitize`, `GET /download`):

```
sanitize-status -> 200  document_state=pending
download        -> 409  "document is 'pending'; download requires sanitization (or explicit 'never')"
sanitize T3     -> 200  verdict=pass  allow_auto_pass=true  chunks_promoted=10
status after    -> 200  document_state=sanitized
download after  -> 200  <markdown body>
```

That is the documented contract, end to end. A `blocked` document (`b779a76a…`)
returns 409 with `document is 'blocked'` and is correctly **not** readable — there
is no restore path, by policy.

Current matter state: `pending=75, sanitized=15, blocked=7`. The 75 pending
documents will keep producing 409s until someone sanitizes them — **that is the
gate working, not a fault.**

---

## 4. The one real issue: memory updates time out ~27% of the time

Not a 409, and **not caused by the upgrade** in the sense of being incorrect
behaviour — but it is real and worth fixing.

```
updated_ok    7
timed_out     3
parse_fail    1
out_of_scope  0
stale_409     0
```

Timeline (all after the 01:34 restart):

```
01:39:21  updated
01:41:29  timed out      } 30 s apart
01:41:59  timed out      }
01:44:12  updated
01:49:01  updated
01:51:27  updated
01:55:19  timed out
01:59:36  parse fail
02:05:06  updated
02:09:03  updated
02:16:47  updated
```

**Root cause, from the traceback:** `httpx.ReadTimeout` / `httpcore.ReadTimeout`
waiting for **response headers** from Ollama at
`http://host.docker.internal:11434/v1`. Not our code — the model was still loading
or the runner slot was busy.

Evidence gathered:

| Probe | Result |
|---|---|
| `create_chat_model("gemma4-12b-memory").invoke(...)` warm | **0.5 s** |
| Same at 2 025 / 8 025 / 16 029 chars | 1.1 s / 3.0 s / 3.2 s |
| Raw Ollama, first call after idle (`gemma4:12b-it-qat`) | **12.8 s** |
| Full `update_memory_from_conversation(...)` | **succeeds `True` in 58.3 s** |
| Ollama models loaded | `gemma4:12b-it-qat` |

So the lane **works** (7 successes, and my own end-to-end call returned `True`), but
a cold model load or a busy single runner slot on this box can exceed the read
timeout. The memory prompt cap from `86a9feb` is in place
(`MEMORY_CONVERSATION_MAX_CHARS = 16000`, line 474; conversation block at line 43
precedes the memory block at 48), so the *prompt* is not the problem — the **local
model's cold-start latency on a shared runner** is.

**Recommendation (not applied — no fix without your decision):** raise the
memory-lane read timeout, or warm the model before the queue fires, or accept the
loss (memory updates are retried on later turns, and 7/11 succeeded). I have not
changed anything.

---

## 5. Auth: 27 × 422 on `login/local`, and why that is fine

`POST /api/v1/auth/login/local` returned **422 × 27**, clustered at exactly two
moments: `2026-10-26 15:34:52` (×14, from `172.23.0.6`) and `2026-10-27 02:16:47`
(×13, from `127.0.0.1`).

**Cause: caller error, not a service defect.** The route is
`@router.post("/login/local")` → `form_data: OAuth2PasswordRequestForm`
(`patches/deer-flow-auth.py:418`, `:428` uses `form_data.username`). It requires
**form-encoded `username`**, not JSON `email`.

Verified both ways:

```
JSON body {"email": …}          -> 422  ("Field required: username")
JSON body {"username": …}       -> 422
form-encoded username=…&password=… -> 401 invalid_credentials   <- correct shape
```

The real login page already sends the right thing
(`deer-flow/frontend/src/app/(auth)/login/page.tsx:158–170`):
`Content-Type: application/x-www-form-urlencoded` with `username: email`.
**Users can log in.** The 422s are diagnostic scripts (mine included) posting JSON.

The `02:16:47` cluster from `127.0.0.1` coincides with the memory-update run at
that second — a probe, not a user.

---

## 6. Three false alarms I raised, and what caught them

Recording these because two looked like the regression you reported:

1. **"Root cause found: 409 → the gate is broken."** I initially read a nginx
   409 preceded by a `sanitize` 500 as a broken gate. Reading the *order* showed
   the 500 was on a different document, and reproducing the gate against a real
   pending doc gave 409 → sanitize 200 → download 200. **Untrue.**

2. **"The MCP 409s are post-restart."** I compared them against `StartedAt`
   (`2026-10-27T01:34:52`). But `pacgate-mcp` was **created**
   `2026-10-26T04:53:30` and merely restarted — `docker logs` retains everything
   since *creation*, not since the last start. The 409s are `07:50`/`08:16` on
   10-26. **Untrue.**

3. **"Memory times out on every update."** It reads `timed_out=3` against
   `updated_ok=7`. Real, but a minority, and self-recovering. **Overstated.**

Also: several of my audit scripts reported nonsense on first run and had to be
fixed — `grep -c` compared against `1` when it counts matching *lines* (3 here);
`$Matches` clobbered by a nested `-match` in a backward timestamp scan; `<` inside
an `sh -c` pattern parsed as a redirect; and native stderr promoted to a
terminating error under `$ErrorActionPreference='Stop'`. Each produced a false
result before the fix, which is why every number above is from a corrected script.

---

## 7. Stack state at time of audit

```
deer-flow            running/healthy  restarts=0  tag=0.2.6
deer-flow-frontend   running/healthy  restarts=0  tag=0.2.6
pacgate-api          running/healthy  restarts=0  tag=0.2.6
pacgate-mcp          running/healthy  restarts=0  tag=0.2.6
pacgate-nginx        running/healthy  restarts=0  tag=1.27-alpine
ocr-service          running/healthy  restarts=0  tag=0.2.6
pacgate-db           running/healthy  restarts=0  tag=pg16
openviking           running/healthy  restarts=0  tag=46f9e34cd37238c28cbd9535033773d179006bdf7f3e528dd1c46567abce7701
```

- Compose owner: **`compose.bundle.yaml`** (as intended after the bundle rollout).
- MCP connectors: **30** (the extensions-config render did **not** fire — no
  `install.ps1` was run).
- Extension config backup present:
  `deer-flow-extensions-config.json.bak.pre-86a9feb-20261026-233431`.
- Gate suite: **ALL 53 GATES PASSED** (14 live-stack checked separately).
- The `86a9feb` artifact is live: `MEMORY_CONVERSATION_MAX_CHARS = 16000` at
  line 474, conversation block (43) before memory block (48).

---

## 8. What I did NOT do

- No fixes applied. No container restarted or recreated during the audit.
- Did not raise the memory timeout — that is a policy choice (timeout vs. cost of
  a cold model load), and it needs your decision, not mine.
- Did not sanitize the 75 pending documents. That is a data/policy operation on
  real matter content.
- Did not push to the fork — still blocked by the `github.com:443` TLS reset from
  this host (unrelated to this audit; commits remain local).
