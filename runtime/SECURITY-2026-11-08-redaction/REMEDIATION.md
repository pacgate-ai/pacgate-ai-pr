# SECURITY — Plaintext credentials in the agent-readable data tree

**Date:** 2026-11-08
**Trigger:** audit follow-up on the 0.2.32 full-stack review
**Severity:** HIGH — clearable credential inside the agent's blast radius
**Status:** REMEDIATED locally. **Rotation still outstanding.**

---

## What was found

`pacgate-ai/deploy/client-bundle/data/` is bind-mounted into `deer-flow` at `/data`.
The sandbox is `LocalSandboxProvider` with `allow_host_bash: true`
(`deer-flow-config.yaml:617-623`), so **agent `bash` runs in the gateway container and
can read `/data` directly** — verified: `ls` and `grep` against the credential docs
both worked from inside the container.

That tree contained three credential documents:

| File | Contents |
|---|---|
| `assets/智库资料收集/智库资料收集/MCP授权/境外法律数据库和网站.md` | overseas DB accounts — **1 plaintext API token** + 4 plaintext passwords |
| `assets/智库资料收集/智库资料收集/MCP授权/法律数据库MCP.md` | 元典 / 北大法宝 / 企查查 — 1 unified password |
| `assets/百宸初建方案文件/清单类文件/百宸AI系统资源接入清单V2.docx` | access inventory (docx) |

### Worse: the credentials had been indexed into pgvector

The KB ingester had chunked both markdown files. **8 chunks contained the credential
text** across 6 duplicate documents (3 versions of each) in tenant `pacgate-law`.

**Containment check — the retrieval gate held.** `pacgate-rag/src/lib.rs:341` appends
`AND c.sanitization_state IN ('sanitized', 'never')` to every retrieval query. All 8
credential chunks were `blocked` (4) or `pending` (4), so **0 were retrievable**:

```sql
select count(*) from kb_chunks c join documents d on c.document_id=d.id
 where c.tenant_id='d64908b0-...' and c.embedding is not null
   and c.sanitization_state in ('sanitized','never')
   and (c.content like '%<token>%' or c.content like '%统一密码%');
-- 0
```

The sanitizer was doing its job. The exposure was the **raw file**, plus the
**possibility** of a future re-ingest or a state flip promoting the chunks.

---

## What was done

1. **Backed up** the three source files and the three tenant doc copies to
   `runtime/SECURITY-2026-11-08-redaction/pre-redaction-backup/` — **outside** any
   mounted tree, so the backup is not itself agent-readable.
2. **Redacted the plaintext API token** to the reference form
   `` `${COURTLISTENER_API_KEY}` `` in all 4 copies of `境外法律数据库和网站.md`
   (1 source + 3 tenant versions). Verified the literal token now appears in
   **0 files** under `data/` — including via `grep` from inside the container.
3. **Redacted plaintext passwords** (5 files) to
   `<REDACTED - see client-bundle/.env or the operator>`.
4. **Purged the credential chunks from pgvector** — 20 chunks across the 6 documents
   (`2327 → 2309` total chunks; the other 18 removed rows were siblings in the same
   documents, not credential-bearing).
5. **Marked all 6 documents `sanitization_state='blocked'`** so a re-ingest cannot
   resurrect the content (`ingest.rs` excludes `blocked` from the replace path
   precisely so a deliberate refusal is not silently overwritten).

### Verified no regression

| Check | Result |
|---|---|
| `cjk_tsquery('资料收集')` | **21** — identical to the pre-remediation baseline |
| `test-sanitization-gate` | ALL ASSERTIONS PASSED |
| `test-connector-registry` | 25 passed, 0 failed |
| `test-legal-journey` | full legal journey PASSED |
| Container health (api, db, mcp, deer-flow, ocr, frontend) | all healthy |
| Chunks missing `content_tsv` | 0 |

---

## Two findings I had to retract

**"`COURTLISTENER_API_KEY` has no live connector" — WRONG.** CourtListener is a
first-class connector in the Rust search registry
(`pacgate-search/src/lib.rs:540`, `CourtListenerConnector`, documented `Active (free)`).
`test-connector-registry` passes 25/25 and lists `courtlistener` in both the
`implemented claims` and `connectors with an impl` sets. The key is **actively consumed**
at `lib.rs:1852`. The connector lives in `pacgate-api`'s `default_router`, not in
`deer-flow-extensions-config.json` — I confused the two registries. No action needed.

**"`QCC_API_KEY` is dormant because the qcc connectors are disabled" — WRONG.** Same
mistake. `QccConnector` is implemented and registered (`lib.rs:435` `env_var:
QCC_API_KEY`). `https://agent.qcc.com/mcp/company/stream` is reachable (HTTP 405 on
HEAD, i.e. live). The 11 `qcc-*` entries in the **deer-flow** config being `enabled:
false` is a deliberate config choice and does not affect the native connector. No
action taken, and **no connector was enabled** — that is a human decision.

---

## What is still outstanding (operator only)

**Rotate the credentials that appeared in these files.** Redaction removes them from
disk and from the vector store, but:

- `境外法律数据库和网站.md` was tracked in `pacgate-ai-pr` history (purged forward-only),
  so its contents must be treated as permanently public.
- The CourtListener token, the 元典 / 北大法宝 / 企查查 passwords, and the overseas DB
  logins were readable in plaintext on this box for months.

Treat every credential in the four originally-leaked files as compromised:

1. CourtListener — regenerate the API token.
2. 元典 / 北大法宝 / 企查查 — change the unified password, then update
   `YUANDIAN_API_KEY`, `PKULAW_API_KEY`, `QCC_API_KEY`, `FYOPEN_API_KEY` in
   `client-bundle/.env`.
3. Overseas legal DBs — rotate each account password.
4. PacGate GitHub account — rotate, per `OPERATOR.md`'s own warning.

After rotating, re-run `test-cross-stack-credentials` and `test-connector-registry`.

---

## Regression guard added

`scripts/test-secret-in-mounted-data.ps1` — fails if any `.env` secret value
(length ≥ 16) appears verbatim in a text file under `deploy/client-bundle/data/`.
It reports the **file and the key name**, never the value. Registered in
`run-all-checks.ps1`.

This closes the gap that let the leak sit unnoticed: the repository's other 90+
gates all inspect *code and config*, and none of them looked at the data tree the
agent can read.
