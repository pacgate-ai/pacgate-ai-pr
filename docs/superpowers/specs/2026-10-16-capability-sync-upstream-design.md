# Capability Sync to Upstream — Design

**Date:** 2026-10-16
**Status:** Approved (design), pending spec review
**Author:** AIPC #1 session
**Target release:** v0.1.32

## Problem

AIPC #1 runs a fully functional v0.1.31 stack. The user wants the capabilities
established on this machine — workflows, API, skills, MCP connectors, matters
(feature/templates), and settings — shared to upstream `origin/main` so other
machines pick them up.

Reconnaissance (2026-10-16) showed **most of this is already upstream**. The
request is therefore not a wholesale sync but a **narrow gap closure**.

## Verified current state

Live stack: **0.1.31** (all 5 images `ghcr.io/jzkk720/*:0.1.31`).

| Capability | Local | Upstream `JZKK720/pacgate-ai-pr` main (`8183295`) | Gap |
|---|---|---|---|
| Workflows | 15 YAML / 222 defs | 15 YAML | ✅ none (byte-identical) |
| API | `crates/pacgate-api/` | present | ✅ none |
| Personas | `crates/pacgate-persona/src/lib.rs` (46 KB) | present | ✅ none |
| Templates | `deer-flow-config.yaml`, `extensions-config.template.json` | present | ✅ none |
| Version pins | `jzkk720/*:0.1.31` | `jzkk720/*:0.1.31` | ✅ none |
| **MCP connectors** | 30 servers (18 enabled) | template = **3 servers** | 🔴 **27 missing** |
| **Skills** | 60 dirs / 142 files | 139 files in `JZKK720/deer-flow` | 🟡 3 missing + delivery broken |
| **Patches** | 18 files | 17 files | 🟡 1 missing |
| **`.env.example`** | 23 keys live | 14 keys | 🟡 6 connector keys absent |

### Key findings

1. **The MCP connector gap is the real defect.** `install.ps1` renders
   `deer-flow-extensions-config.json` from a 3-server stub template. The 27
   legal connectors exist **only** in the rendered file, which is gitignored.
   A fresh machine gets 3 connectors, not 30. This is the same defect AGENTS.md
   documents as "install.ps1 DESTROYS the MCP connector config".

2. **Skills never reach a fresh machine.** The image bakes **0** skills
   (verified: `docker run --rm --entrypoint sh ghcr.io/jzkk720/deer-flow-pacgate:0.1.31 -c "ls /app/skills/public | wc -l"` → `0`).
   The compose mount is `../../../deer-flow/skills/public` — a mono-folder-only
   relative path. A fresh upstream deploy has no sibling `deer-flow` clone, so
   the mount resolves to nothing and the agent gets no skills.

3. **`vaquill` embeds its key in the URL**, not a header:
   `https://mcp.vaquill.ai/s/vq_key_...`. It is the one connector that breaks
   the uniform header-substitution pattern.

4. **Two `.env` keys are dead.** `COURTLISTENER_API_KEY` and `FYOPEN_API_KEY`
   are set in `.env` but referenced by **no** connector in the rendered config.

5. **`FIRECRAWL_API_KEY` is hardcoded** in the rendered file and absent from
   `.env` entirely — a new key, not merely a documentation gap.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| MCP connector sharing | **(a)** Expand the template to all 30 servers with `${VAR}` placeholders | Only option where a fresh machine gets 30 connectors with no manual work; directly fixes the documented defect |
| Skills delivery | **(A)** Bake into the image | Only option where `docker compose pull` alone delivers the full capability set; matches how api/mcp/frontend/ocr already ship |
| Matters | **Feature/templates only** — no client data | The `matters` table holds engagement records with FK cascades into `documents`, `kb_chunks`, `redaction_ledger_rows`. Pushing those would ship client/test data to a **public** repo |

## Scope — 5 workstreams

| # | Workstream | Repo | External blocker |
|---|---|---|---|
| W1 | Expand MCP connector template 3 → 30 | `pacgate-ai-pr` | none |
| W2 | Bake skills into the image | `pacgate-ai-pr` + CI | none |
| W3 | Merge PR#1 (3 skills + tool-policy) | `JZKK720/deer-flow` | **needs JZKK720 action** |
| W4 | Push `deer-flow-uploads-middleware.py` | `pacgate-ai-pr` | none |
| W5 | Add 6 connector keys to `.env.example` | `pacgate-ai-pr` | none |

---

## W1 — Connector template expansion

### Placeholder map

Derived from the live rendered config (`deer-flow-extensions-config.json`).

| Connector(s) | Count | Substitution |
|---|---|---|
| `openviking` | 1 | header `X-API-Key: ${OPENVIKING_ROOT_API_KEY}` *(already present)* |
| `pacgate`, `officecli` | 2 | no key |
| `firecrawl` | 1 | env `FIRECRAWL_API_KEY: ${FIRECRAWL_API_KEY}` |
| `yuandian-{law,case,company,securities}` | 4 | `Authorization: Bearer ${YUANDIAN_API_KEY}` |
| `pkulaw-*` | 9 | `Authorization: Bearer ${PKULAW_API_KEY}` |
| `qcc-*` (http) | 10 | `Authorization: Bearer ${QCC_API_KEY}` |
| `qcc-document-mcp` (stdio) | 1 | env `QCC_DOCUMENT_AUTHORIZATION: Bearer ${QCC_API_KEY}` |
| `vaquill` | 1 | ⚠️ **URL-embedded**: `https://mcp.vaquill.ai/s/${VAQUILL_API_KEY}` |
| `ansvar` | 1 | `Authorization: Bearer ${ANSVAR_API_KEY}` |

`Accept: application/json, text/event-stream` is a constant on all HTTP
connectors — **not** templated.

### `install.ps1` change

Replace the single hardcoded substitution with a generic pass:

```powershell
$df = Get-Content $dfTemplate -Raw -Encoding UTF8
foreach ($k in $envVars.Keys) { $df = $df.Replace('${' + $k + '}', $envVars[$k]) }
# then scan for leftover ${...} and WARN (do not exit)
```

Two behaviours preserved deliberately:

- **`OPENVIKING_ROOT_API_KEY` stays mandatory.** The existing guard is correct:
  a missing key breaks deer-flow memory recall (OV-2a), and compose mounts the
  file `:ro`.
- **All other keys stay optional.** A missing connector key must degrade to
  "fewer sources", never fail the install. Leftover `${...}` is **reported, not
  fatal**.

### Enabled/disabled state

The template carries the **current** enabled flags (18 enabled / 12 disabled).
The 12 disabled are `qcc-*` (11) + `ansvar` — a pre-existing operator decision,
not a defect. Preserved as-is.

---

## W2 — Skills baked into the image

### Mechanism

- **CI** (`build-ghcr.yml`): new step clones `JZKK720/deer-flow` at a pinned
  SHA, copies `skills/public` → `deploy/deer-flow-pacgate/skills/public`.
- **Dockerfile**: `COPY deploy/deer-flow-pacgate/skills/public /app/skills/public`
- **compose**: the `../../../deer-flow/skills/public` mount becomes a
  **commented-out dev override**. The image is the source of truth; the mount
  exists only for live skill editing during development.
- **Pin**: `SKILLS_REF` build arg, so the skills version is explicit and
  reproducible.

### ⚠️ Ordering dependency on W3

`SKILLS_REF` must resolve to a ref that **contains the 3 skills from W3**.
`JZKK720/deer-flow` main currently has **139** files; the 3 skills live only on
`pacgate-ai/deer-flow` branch `pacgate-layer-fixes-2026-10` (= `19021f7f`).

Two valid resolutions — pick one at implementation time:

| Option | `SKILLS_REF` | Trade-off |
|---|---|---|
| **W3 first** | `JZKK720/deer-flow@main` | Cleanest; requires the JZKK720 merge before the v0.1.32 build |
| **Pin the fork** | `pacgate-ai/deer-flow@19021f7f` | Unblocks the build immediately; the pin must be re-pointed to `main` after W3 merges |

**Default: W3 first.** If the JZKK720 merge stalls, fall back to pinning the
fork SHA so the release is not blocked. Either way the pin is explicit — never
a floating branch name.

### Why the mount must be demoted

If both the baked copy and the mount are active, they can silently disagree —
the mount wins at runtime, so a stale image would look correct on this machine
and broken on a fresh one. Demoting the mount to a commented dev override makes
the image authoritative and the divergence visible.

### Known implementation risk (NOT verified)

The platform-root `.dockerignore` may exclude the new path. This is the same
class of bug that previously broke `deploy/deer-flow-src/` (BuildKit
`CopyIgnoredFile`). **Must be checked during implementation, not assumed.**

---

## W3 — Merge PR#1 (deer-flow)

PR#1 on `JZKK720/deer-flow` (`pacgate-ai:pacgate-layer-fixes-2026-10 → main`)
is open and carries:

- 3 skills absent from `origin/main`: `antitrust-compliance`, `arbitration`,
  `bankruptcy-restructuring` (all added in `19021f7f`, all PacGate-authored —
  0 in bytedance upstream)
- `tool_policy.py` prefix-aware matching
- `skill_storage.py` eval-fixture exclusion

Merging PR#1 is the entire fix for W3. **Requires JZKK720 action** — our PAT
has `push=False` on `JZKK720/*`.

---

## W4 — Push the missing patch

`deer-flow-uploads-middleware.py` exists locally (14,282 bytes) and is mounted
in `compose.bundle.yaml`, but is absent from upstream's `patches/` (17 vs 18).
Push to fork/main → PR.

---

## W5 — `.env.example` connector keys

Add 6 keys:

```
FIRECRAWL_API_KEY=
YUANDIAN_API_KEY=
PKULAW_API_KEY=
QCC_API_KEY=
VAQUILL_API_KEY=
ANSVAR_API_KEY=
```

### Deliberately excluded

| Key | Reason |
|---|---|
| `PACGATE_MODEL_{MAIN,MID,LOW}` | Per-machine model roster — user directive 2026-09-21 |
| `OPENVIKING_CONF_CONTENT` | Rendered by `install.ps1`, not user-set |
| `COURTLISTENER_API_KEY` | **Dead** — referenced by no connector |
| `FYOPEN_API_KEY` | **Dead** — referenced by no connector |

---

## Delivery sequence

```
1. Local edits (W1, W2, W5) → wrapper repo
2. Push fork/main → PR to JZKK720
3. Merge PR#1 (W3) — JZKK720 action
4. Push W4 patch
5. Tag v0.1.32 → CI builds → pull → verify
```

**Ordering note:** step 3 (W3) must complete **before** step 5, because the
`SKILLS_REF` pin must resolve to a ref containing the 3 skills. If W3 stalls,
pin the fork SHA `19021f7f` instead (see W2 → Ordering dependency).

## Verification

| Workstream | Check | Expected |
|---|---|---|
| W1 | Render from template with a test `.env` | **30 servers**, 0 leftover `${...}` |
| W2 | `docker run --rm --entrypoint sh <img> -c "ls /app/skills/public \| wc -l"` | **60** |
| W3 | `git ls-tree -r origin/main -- skills/public \| wc -l` | **142** |
| W4 | `git ls-tree -r upstream/main -- deploy/client-bundle/patches \| wc -l` | **18** |
| W5 | Key-set diff `.env.example` vs live `.env` | Only per-machine keys differ |

**W1 negative control:** render with a `.env` that omits `PKULAW_API_KEY` and
confirm the install still succeeds with a warning — proving optional keys
degrade rather than fail. A bare "30 servers" count proves nothing about the
failure path.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Template publishes all 30 connector URLs to a **public** repo | 🟡 business-intel exposure (which vendors the firm uses) | Accepted with decision (a). Keys stay in `.env` — no credential leak |
| `.dockerignore` excludes the baked skills path | 🟡 build failure | Check during implementation; the `deploy/deer-flow-src/` precedent |
| Cross-repo build dependency (CI clones `deer-flow`) | 🟡 CI fragility | Pin `SKILLS_REF`; a skill edit needs an image rebuild |
| Baked skills drift from the live mount | 🟡 silent divergence | Demote the mount to a commented dev override |
| W3 blocked on JZKK720 | 🔴 external | Cannot be resolved from this machine; flag to the developer |

## Out of scope

- Client data (`matters` rows, `documents`, `kb_chunks`, `redaction_ledger_rows`)
- Per-machine settings (`.env` values, model roster, `GATEWAY_CORS_ORIGINS`)
- Credential rotation (separate active incident)
- The `pacgate-law` wrapper repo (local-only by design, no remote)
