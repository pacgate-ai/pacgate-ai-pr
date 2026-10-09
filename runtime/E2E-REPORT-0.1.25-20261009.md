# E2E verification report — v0.1.25 upgrade (2026-10-09, final)

## Upgrade summary

| Item | State |
|---|---|
| Upstream tag | v0.1.25 @ 003a4f93 (run#25, all 5 images published to ghcr.io/jzkk720) |
| Upstream main | efaeb50f = tag + 3 commits (benchmark docs x2, harden-release-tooling) |
| Wrapper sync | b6c7875 (adopt 0.1.25) + be4df9b (re-apply patches) + this session's delta adoption |
| Images pulled | 5/5, digests match GHCR manifests exactly |
| Containers recreated | 5/5 on 0.1.25 (api, mcp, deer-flow, frontend, ocr) |
| Untouched | pacgate-db, pacgate-nginx, openviking, qm-* (Up 2 days, digest-pinned) |

## Image digests (verified vs GHCR)

| Image | Local ID | GHCR manifest digest |
|---|---|---|
| pacgate-api:0.1.25 | 3ab43036a8ec | sha256:3ab43036... |
| pacgate-mcp:0.1.25 | 307383bd26c7 | sha256:307383bd... |
| deer-flow-pacgate:0.1.25 | 9341a70f8c47 | sha256:9341a70f... |
| deer-flow-frontend-pacgate:0.1.25 | 6aaac71d1c28 | sha256:6aaac71d... |
| ocr-service:0.1.25 | df9bdc781a35 | sha256:df9bdc78... |

## E2E lanes — FINAL RESULTS

| Lane | Result | Evidence |
|---|---|---|
| Containers up | ✅ 5/5 Up, 0 restarts | docker ps |
| pacgate-api binary | ✅ 0.1.25 baked | image label org.opencontainers.image.version=0.1.25; binary contains "0.1.25" x5 |
| pacgate-api auth | ✅ | login → token issued |
| Matters | ✅ 10 matters | GET /pacgate/api/matters |
| Workflows | ✅ 222 workflows / 222 categories | GET /pacgate/api/workflows |
| Connectors | ✅ 9/10 available | yuandian, pkulaw, qcc, fyopen, courtlistener, sec_edgar, gleif, vaquill, eur-lex |
| Matter memory lane | ✅ | GET /api/matters/{id}/memory → version 2.0 payload |
| MCP server | ✅ 19 tools | initialize → session-id → tools/list |
| MCP tool execution | ✅ | pacgate_list_matters → 3910B real tenant data |
| deer-flow login | ✅ | form login → csrf cookie |
| deer-flow models | ✅ 8 models | GET /api/models |
| deer-flow agents | ✅ 2 agents | ocr-extractor + sanitizer |
| **Memory card** | ✅ **HTTP 200, 35,404B** | GET /api/memory (the 0.1.25 fix — was 500 pre-0.1.25) |
| Frontend :8090 | ✅ HTTP 200 | |
| nginx :8089 | ✅ HTTP 200 | |
| DB integrity | ✅ 1 tenant / 3 users | unchanged |
| DB data | ✅ 100 documents, 19 extractions, 31 sanitizer jobs | unchanged |
| Summarization | ✅ enabled, trigger 5000/keep 4000, nemotron-30b-summarizer | live config in container |
| Model routing | ✅ enabled, nemotron default | live config |
| LLM lane | ✅ nemotron 30B: cold 43.8s → warm 4.8s, 46%/54% CPU/GPU | ollama ps |
| Embedder | ✅ nomic-embed-text 768-dim, 3.4s | /api/embeddings |
| MCP connectors | ✅ 18/30 enabled (30 configured) | 12 qcc + ansvar disabled — PRE-EXISTING (same in pre-upgrade backup) |
| Patch mounts live | ✅ tool-policy (2 hits), skill-storage (3 hits), adapter 401-fix (6 hits), vision (1 hit) | in-container grep |
| Skills tree | ✅ 60 skill dirs mounted | /app/skills/public |
| OCR weights | ✅ PP-OCRv4 det/rec/cls persisted in paddleocr-models volume | /root/.paddleocr |
| OpenViking | ✅ healthy, digest-pinned, untouched | Up 2 days |
| qm stack | ✅ 7 containers healthy, digest-pinned, untouched | Up 2 days |

## Notes

1. **/version endpoint**: 404 via nginx on both /pacgate/version and /pacgate/api/version —
   the version surface is the image LABEL (org.opencontainers.image.version=0.1.25) +
   the binary string, not an HTTP route in 0.1.25. Not a regression (same in 0.1.24).
2. **qcc/ansvar MCP servers disabled**: pre-existing state (verified identical in the
   pre-upgrade backup). The qcc Bearer tokens are present in the config but the servers
   are enabled:false — likely disabled earlier due to endpoint issues. NOT a 0.1.25 regression.
3. **First nemotron call 43.8s**: cold model load after container recreation (expected).
   Warm: 4.8s. GPU placement 46%/54% CPU/GPU split (25GB model on 16GB VRAM — expected MoE behavior).
4. **deer-flow AUTH_JWT_SECRET warning**: benign — auto-generated secret persisted to
   .jwt_secret, sessions survive restarts (the backup contains this file).

## Rollback

Images 0.1.24 still present locally. To roll back:
```
docker compose -f compose.bundle.yaml up -d --force-recreate --no-deps pacgate-api pacgate-mcp deer-flow deer-flow-frontend ocr-service
# after temporarily re-pinning 0.1.24 in compose.bundle.yaml
```
Backup: runtime/backup-pre-0.1.25-20261009/
