# AIPC1 upgrade — v0.2.24 → v0.2.30 (upstream/main 28d73c4)

Date: 2026-11-05
Machine: AIPC1 (`C:\Users\pacga\github-pr\pacgate-law`)
Target: `upstream/main` = `28d73c4`, which is **3 commits ahead of the `v0.2.30` tag** (`af3cde5`).

## Why upstream/main and not the tag

`v0.2.30` is not the head. Three commits landed after it:

| Commit | Subject |
|---|---|
| `af043a7` | fix(install): restore the 'Cannot refresh the repo' collision headline |
| `a78073a` | **feat(vlm): unify OpenViking VLM onto nemotron-3.5-bolt, retire gemma4:12b** |
| `28d73c4` | fix(deer-flow): extend convergence discipline to research iteration + over-scoping |

`a78073a` is the one that matters: it performs the OpenViking VLM cutover **and** fixes a
latent installer defect (OpenViking reads the bind-mounted `ov.conf` FILE, not the
`OPENVIKING_CONF_CONTENT` env var, which only seeds it on first boot). Merging the tag
alone would have left the VLM on a retired tag.

## Merge method

The two histories are unrelated, so no `git merge`. Per-file 3-way merge
(`git merge-file`) with `v0.2.24` as base:

- **7 files** changed both locally and upstream → 3-way merged (1 conflict, resolved)
- **39 files** upstream-only → adopted verbatim from `upstream/main`
- **77 local-delta files** preserved (verified present after the merge)

## Local deltas that had to be repaired

| File | Problem | Fix |
|---|---|---|
| `deer-flow-config.yaml` | Upstream renamed model keys `gemma4-12b-local` → `nemotron-bolt-7b-local`; our local `subagents:` block still pinned the old key in **5 of 10 agents** → dangling reference to a model that no longer exists | Repointed all 5 to `nemotron-bolt-7b-local` |
| `compose.bundle.yaml` + `compose.prod.yaml` | Our 0.2.x port **dropped** upstream's `./deer-flow-skills` mount. `test-skill-evolution.ps1` E3 failed on both lanes | Restored the mount (additive — different destination from our `/app/skills/public` superset mount) |
| `test-pdf-freshness.ps1` | Our local delta dropped upstream's `$mdDirty` guard, so `$byMtime` fired on mtime alone → false "uncommitted edit" | Restored the guard (matches upstream) |
| `ensure-context-capped-model.ps1` | Still built the retired `gemma4-legal:12b-chat` derivative and aborted the whole run when its source tag was absent | Dropped the gemma4 entry; kept the qwen3.8 Mid-tier derivative |
| `ollama-models.txt` | Merge conflict: our gemma4 capped-derivative block vs upstream's 74B block | Kept upstream's 74B block + the qwen3.8 derivative; removed the retired gemma4 tags |

## Model roster after the upgrade

| Tier | Tag | Status |
|---|---|---|
| Main | `deepseek-v4.1-flash:cloud` | cloud |
| Mid | `qwen3.8-legal:27b-mid` | **rebuilt** locally (num_ctx 32768) from `qwen3.8:27b-mtp-q4_K_M` |
| Low | `nemotron-3.5-bolt:e4b-q8_0` | 9.8 GB, 100% GPU, ctx 65536 |
| Fallback | `ornith-1.5:9b` | **pulled** (was missing) |
| Embeddings | `nomic-embed-text:latest` | present |
| OpenViking VLM | `nemotron-3.5-bolt:e4b-q8_0` | swapped in live `ov.conf`, root_api_key preserved |

`gemma4` is retired and no longer referenced by any active config.

## Images

All five pinned to `0.2.30` and pulled from ghcr:

| Image | Digest |
|---|---|
| `pacgate-api` | `sha256:cd729ce1a841b44bcc18887b212aef0b6c9cace25ee8689f4fe5276307063565` |
| `deer-flow-pacgate` | `sha256:b86e972f760856c72362ff84cb158ca165bc28eea047b5eae7131e2c1316a30b` |
| `deer-flow-frontend-pacgate` | `sha256:9a329f2c1a2396b603f161b06e8c13256aaa9d9f80e4fe1950a460089ae2205d` |
| `pacgate-mcp` | `sha256:6e48e2b2265ce1b0f1151162f3d758aad544d2c7f143586d298fef61dd793e74` |
| `ocr-service` | `sha256:2a0b3fd921de22a852aa810b3a9eb7081800e6f84806116ba8959676ab384283` |

`/version` reports `{"revision":"436d41ee39e7","version":"0.2.30"}`.

## Verification

### Runtimes — all healthy

`pacgate-api`, `deer-flow`, `deer-flow-frontend`, `pacgate-mcp`, `ocr-service`,
`openviking`, `pacgate-db`, `pacgate-nginx` — 8/8 healthy.
`qm-pacgate` (6 containers) untouched and still up.

### Functional

| Area | Result |
|---|---|
| Low tier inference | `OK` in 25.1 s |
| Mid/fallback inference | `OK` (needs >20 tokens of headroom — reasoning burns ~104 chars first) |
| OpenAI-compat + `reasoning_effort: none` | content returned, `finish=stop` |
| `json_schema` structured output | valid JSON, CJK party name preserved |
| GPU residency | **100% GPU**, ctx 65536 (`test-ollama-gpu-residency.ps1` PASS) |
| Sanitizer e2e | **PASS** — 22 assertions, ID/phone redacted, ledger + audit written |
| Document generation | **19/19 PASS**, real `.docx`, CJK round-trip |
| Doc-gen soak | **8/8 runs HTTP 200**, 0 failures |
| MCP handshake | `initialize` + `tools/list` → **24 tools** |
| VectorDB | 2314 chunks, all with `content_tsv`; pgvector 0.8.6, dim 768 |
| CJK fulltext (migration 009) | `资料收集` **0 → 21** matches vs the old english parser |
| Subagents | 10/10 resolve to an **installed** tag |
| Playbook mount | `/mnt/playbooks/nda-playbook.md` reachable |
| Seed skills | 5/5 visible at the agent's skills root |

### Gate suite

**77 PASS, 1 FAIL, 3 SKIP.**

- **FAIL** `test-release-provenance.ps1` — structural, not a regression. It compares the
  image's `org.opencontainers.image.revision` (`436d41e`, upstream's build) against
  **our HEAD**, which is a different lineage with 77 local deltas. It can never pass on
  a fork. The images themselves are correct: all 6 share revision `436d41e` and the tag
  is annotated.
- **SKIP** `test-rust-workspace.ps1` (no cargo), `test-model-picker-e2e.ps1` and
  `test-agent-mcp-e2e.ps1` (no deer-flow credential). All environmental.

## Known gaps

1. **`deploy/deer-flow-pacgate/config.yaml` still names `gemma4:12b-it-qat`** (models[0],
   memory, title). It is baked into the image but **bind-mounted over** by
   `client-bundle/deer-flow-config.yaml`, so it is dormant on this stack. It is an
   upstream bug — reported, not silently rewritten.
2. **`scripts/audit-model-tags.ps1` still lists gemma4** in its header comments. Cosmetic;
   the gate passes.
3. **`test-release-provenance.ps1`** needs a fork-aware mode before it can be green here.
