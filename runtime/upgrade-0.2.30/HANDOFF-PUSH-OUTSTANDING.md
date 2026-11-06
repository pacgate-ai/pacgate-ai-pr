# HANDOFF — AIPC1 v0.2.30 upgrade: **PUSH COMPLETE**

Date: 2026-11-05, resolved 2026-11-06
Status: **DONE. Code, stack, and push all complete and verified.**

## Push — resolved

`aipc1/v0.2.30-sync` is on the fork at **`a9c86c3`** (verified via the GitHub API):

```
https://github.com/pacgate-ai/pacgate-ai-pr/tree/aipc1/v0.2.30-sync
```

It took 5 attempts over a flaky `github.com:443`; the connection succeeded once the
VPN route stabilised. What actually unblocked it:

- removing the stale `http.curloptResolve = github.com:443:140.82.112.3` pin from
  `C:/Users/pacga/.gitconfig` (it sent git to a dead IP), and
- `-c http.sslBackend=openssl`, which is the backend that finally connected.
  `schannel` failed with `Recv failure: Connection was reset` mid-HTTP/2.

**Keep the removed pin removed.** If pushes start timing out again, retry rather than
editing config — the failure is the VPN route, not the repo.

## Upstream currency — nothing outstanding

Re-checked 2026-11-06 with `github.com` reachable:

| Check | Result |
|---|---|
| `git fetch upstream --tags --prune` | succeeded |
| `JZKK720/pacgate-ai-pr` `main` | `28d73c4` — **the commit we merged** |
| `git rev-list --count 28d73c4..upstream/main` | **0** |
| Newest tag | `v0.2.30` (`436d41e`) |
| `pushed_at` | `2026-11-05T08:10:07Z` |

There are **no fixes or commits ahead of what was merged**. The `v0.2.30` tag is 3
commits *behind* `main`; `a78073a` (the VLM retirement) is in `main` and was included.

## Subtree completeness vs `28d73c4`

889 upstream files: **40 differ** (the intentional local deltas) and **3 are absent**
because they were deleted in HEAD *before* this upgrade — `audit-recursion-regressions.ps1`,
`diagnose-github-egress.ps1`, `test-chat-artifact-durability.ps1`. They were never in
this fork's history (`git log` finds no commit that ever added them), so they are
upstream scripts deliberately not carried here, not a merge omission.

## Stack state (verified 2026-11-06, 26 h uptime)

8/8 healthy on `0.2.30`; `/version` → `revision 436d41ee39e7`, `version 0.2.30`.
`qm-pacgate` (6 containers) untouched, 46 h uptime.

## Caveats to carry forward

- `test-release-provenance.ps1` FAILS by design on a fork: it compares the image's
  `org.opencontainers.image.revision` (`436d41e`) against **HEAD**, a different lineage
  with 77 local deltas. It cannot pass here. Do not "fix" it by editing the gate; it
  needs a fork-aware mode.
- The 3 SKIPs are environmental: no cargo (`test-rust-workspace`), no deer-flow
  credential (`test-model-picker-e2e`, `test-agent-mcp-e2e`).
- `deploy/deer-flow-pacgate/config.yaml` still names `gemma4:12b-it-qat` — an upstream
  bug, dormant because the live compose bind-mounts `client-bundle/deer-flow-config.yaml`
  over it. Reported, not silently rewritten.
- `deploy/client-bundle/.env` was edited (Low tier → `nemotron-3.5-bolt:e4b-q8_0`,
  OpenViking VLM env → nemotron). It is gitignored, so it did not travel with the push.