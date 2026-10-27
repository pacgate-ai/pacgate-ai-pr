"""Audit the document sanitization gate across every state.

Phase 1 evidence only - reproduces behaviour, fixes nothing.

Correct routes (from deploy/pacgate-mcp/server.py):
    pacgate_verify_sanitized  -> GET  /api/documents/:id/sanitize-status
    pacgate_sanitize_document -> POST /api/documents/:id/sanitize
    read                      -> GET  /api/documents/:id/download

Usage: probe-doc-gate.py <doc-id> [<doc-id> ...]
"""
import json
import os
import sys
import urllib.error
import urllib.request

API = os.environ["PACGATE_API_URL"].rstrip("/")


def req(path, body=None, token=None, timeout=180):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(API + path, data=data, headers=headers,
                               method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(r, timeout=timeout) as x:
            return x.status, x.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return -1, f"{type(e).__name__}: {e}"


def flat(s, n=200):
    return " ".join(s.split())[:n]


def state_of(info):
    # The API returns `document_state` (plus `chunk_states`, `latest_job`,
    # `held_for_review`). Docs and the MCP wrapper call it sanitization_state,
    # but that key is not what /sanitize-status emits - reading the wrong key
    # silently reported state=None on two real documents.
    if isinstance(info, dict):
        return (info.get("document_state")
                or info.get("sanitization_state")
                or info.get("state"))
    return None


st, body = req("/api/auth/login", {
    "email": os.environ["PACGATE_API_EMAIL"],
    "password": os.environ.get("PACGATE_API_PASSWORD", ""),
})
token = json.loads(body)["token"]
print("login:", st, "\n")

for doc in sys.argv[1:]:
    print(f"===== {doc} =====")
    s, info = req(f"/api/documents/{doc}/sanitize-status", token=token)
    try:
        info = json.loads(info)
    except Exception:
        pass
    state = state_of(info)
    print(f"  sanitize-status   -> {s}  state={state}  {flat(str(info))}")

    s, b = req(f"/api/documents/{doc}/download", token=token)
    print(f"  download          -> {s}  {flat(b)}")

    if state == "pending":
        s, b = req(f"/api/documents/{doc}/sanitize", {"data_level": "T3"}, token=token)
        print(f"  sanitize T3       -> {s}  {flat(b, 240)}")
        s, info2 = req(f"/api/documents/{doc}/sanitize-status", token=token)
        try:
            info2 = json.loads(info2)
        except Exception:
            pass
        print(f"  status after      -> {s}  state={state_of(info2)}")
        s, b = req(f"/api/documents/{doc}/download", token=token)
        print(f"  download after    -> {s}  {flat(b, 120)}")
    print()
