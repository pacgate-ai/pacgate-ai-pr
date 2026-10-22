# Root-cause analysis — "more e2e errors, document did not upload" (2026-10-10)

## Direct answers to the five questions

| Question | Answer | Evidence |
|---|---|---|
| Did you upgrade to v0.1.25 and pin upstream/ghcr? | **YES — done 2026-10-09** | All 5 pacgate images run `ghcr.io/jzkk720/*:0.1.25`, digests match GHCR manifests (`E2E-REPORT-0.1.25-20261009.md`); upstream tag `v0.1.25` @ `003a4f93`, wrapper synced to it |
| Did you re-audit after the upgrade? | **YES** | `BENCHMARK-REPORT-2026-10-10-v0.1.25.md` — Karpathy audit K1–K9 all PASS, all lanes PASS, memory lanes PASS, qm re-audit PASS |
| Did you restart all containers? | **YES — the 5 pacgate containers** were recreated on 0.1.25 (Up ~1h at audit time); pacgate-db/nginx/openviking/qm were untouched by design (digest-pinned, stateful) | `docker ps` |
| Did you finish the full smoke test with benchmark reports? | **YES** | Benchmark report §2 "ALL LANES PASS" + E2E report final table all ✅ |
| "This entire build is decoupled — why?" | **It is NOT decoupled.** The failures you saw today are a **host-side Ollama outage + a retry bug**, not a version/deployment problem | see below |

## What actually happened today (timeline, local = UTC+8)

| Local time | Event |
|---|---|
| 13:39:51 | Last LLM call served by the OLD Ollama instance |
| 16:56:40 | Old Ollama loads `ornith-1.5:9b` (last activity) |
| 16:57:27 | Old Ollama's last log write — **then it goes down** |
| 16:59:29–16:59:51 | **Run 1 fails**: user uploads 定制服务协议（签署版）.docx on thread `5a0b52fe`, picks **deepseek-v4.1-flash-cloud**, asks for parse + summary + PDF. deer-flow → Ollama → **connection refused** (Ollama is down). 3 retries, all fail. Run `2697fce5` → error "Connection error." |
| 16:59:58 | **New Ollama instance starts** (server.log begins; process PID 22468, up since then) |
| 17:00:20–17:06:22 | **Run 2 (retry) fails differently**: user retries on the same thread with **nemotron (local)**. Two problems: (a) the retry run's `additional_kwargs` is **EMPTY** — the file context was lost, so the model replied "您还没有上传或粘贴需要解析的文件" (please upload a file); (b) the agent's second LLM call hit a **transient connect-phase failure** (no GIN log = TCP never arrived; Ollama was serving other requests 7s later). Run `ef4969ba` → error "Connection error." |
| 17:15:03–17:19:16 | **Run 3 SUCCEEDS**: new thread `eb5f6381`, new upload (智能体监管全球版图-比较研究.docx), nemotron — file visible, LLM calls 200, run `65f9a41d` → **success**, input bounded at 32,770 tokens |

## Root causes (3 distinct, none are the v0.1.25 build)

1. **Ollama outage 16:57:27–16:59:58 local (~2.5 min)** — the host Ollama process
   went down/restarted. Run 1 fell entirely inside this window. The new instance
   has been stable since (up 45+ min at analysis time).
   - **Side observation (NOT a contributor — corrected on further evidence)**:
     `hermes-web` is in a crash-restart loop (RestartCount 1000+, dies every
     ~27s, exit 1) — but the cause is `[config-migrate] ERROR: Permission denied:
     '/opt/data/SOUL.md'` (bind-mount perms on `hermes-agent/data/`), and it dies
     in cont-init BEFORE any model call, so it does not touch Ollama. Its live
     config (`data/config.yaml`) already has the correct model
     `gemma4:12b-it-q8_0`. Fix separately: repair perms on
     `hermes-agent/data/SOUL.md` or remove the stale file.

2. **Retry loses file context (deer-flow bug, upstream code)** — when a run is
   retried on the same thread, the new run's `kwargs_json.input.messages[0].
   additional_kwargs` is `{}` — the `files` array from the original message is
   not carried over. The model then cannot see the uploaded document and asks
   the user to upload it again. This is why the user perceives "document did
   not even upload" — the upload DID land (file + converted .md are on disk in
   the container, verified), but the retry run could not see it.

3. **Transient connect-phase failure on run 2's second LLM call** — the agent's
   first call streamed 6m1s (200 OK, 620 tokens), then the next call failed at
   TCP connect with no server-side trace. Momentary; the 09:15 run on a fresh
   thread worked normally. Single-runner-slot contention (OLLAMA_NUM_PARALLEL=1,
   memory updater + agent sharing the slot) plus the hermes-web churn are the
   likely background stressors.

## What is NOT the cause

- **Not the v0.1.25 upgrade** — the successful run 3 ran on the same 0.1.25
  images with the same config; summarization config (5000/4000) is live.
- **Not a "decoupled build"** — all 5 images are the pinned GHCR 0.1.25 set,
  patch mounts verified in-container, MCP 141 tools loaded, memory card 200.
- **Not the upload path** — `POST /uploads` returned 200 and the file +
  markitdown-converted .md are on disk.

## Recommended actions (ordered)

1. **Fix hermes-web's SOUL.md permission** (stop the 1000+-restart crash loop,
   unrelated to Ollama but noisy): the container init fails with
   `Permission denied: '/opt/data/SOUL.md'`. Repair the file's ACL on
   `C:\Users\pacga\github-pr\hermes-agent\data\SOUL.md` (owner
   `PACGATE-AI01\pacga` — grant the Docker Desktop user read/write) or move it
   aside; the loop then stops.
2. **Retry-with-file-context bug**: file an upstream deer-flow issue / local
   patch — carry `additional_kwargs.files` into retry runs on the same thread.
   Interim user guidance: after a failed run, start a NEW thread and re-attach
   the file (that path is verified working — run 3).
3. **Optional resilience**: raise `OLLAMA_NUM_PARALLEL` or stagger the memory
   updater so it does not contend with the agent's first call on the single
   runner slot.
4. **Do NOT re-run the upgrade** — nothing about the deployment needs changing.

## Verification commands used (evidence trail)

- `docker ps` — all 5 pacgate images on 0.1.25
- `docker logs deer-flow` — run outcomes, MCP init (141 tools), upload 200s
- `docker exec deer-flow python3` → Ollama `/api/tags` + `/v1/chat/completions`
  from INSIDE the container — both 200 (network path healthy now)
- `deerflow.db` `runs` table — stored status/model/error per run
- `%LOCALAPPDATA%\Ollama\server*.log` — the outage window + new instance start
- `docker inspect hermes-web` — RestartCount 1098, exit 1 loop
