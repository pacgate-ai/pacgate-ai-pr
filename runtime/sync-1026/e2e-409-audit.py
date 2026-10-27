"""Audit the document read path end-to-end, authenticated, from inside deer-flow.

Phase 1 evidence-gathering only: reproduce whatever the chat session hits and
report it. It does NOT fix anything.

Reads: PACGATE_API_URL, PACGATE_MATTER_ID, PACGATE_API_EMAIL, PACGATE_API_PASSWORD
Uses only the stdlib so no install is needed inside the container.
"""
import json
import os
import urllib.error
import urllib.request

API = os.environ["PACGATE_API_URL"]
MATTER = os.environ["PACGATE_MATTER_ID"]
EMAIL = os.environ["PACGATE_API_EMAIL"]
PASSWORD = os.environ.get("PACGATE_API_PASSWORD", "")


def call(path, body=None, token=None, method=None, timeout=30):
    url = API.rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method=method or ("POST" if body else "GET"))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
            try:
                return r.status, json.loads(raw)
            except Exception:
                return r.status, raw[:400]
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw[:400]
    except Exception as e:  # noqa: BLE001 - report, do not crash the audit
        return -1, f"{type(e).__name__}: {e}"


print("=== 1. login ===")
st, tok = call("/api/auth/login", {"email": EMAIL, "password": PASSWORD})
print("login:", st)
token = tok.get("token") if isinstance(tok, dict) else None
print("token_present:", bool(token))
if not token:
    print("BODY:", str(tok)[:300])
    raise SystemExit("cannot continue without a token")

print("\n=== 2. matter document inventory ===")
st, docs = call(f"/api/matters/{MATTER}/documents", token=token)
print("documents:", st, "type:", type(docs).__name__)
items = docs if isinstance(docs, list) else (docs.get("items") or docs.get("documents") or [])
print("count:", len(items))

states = {}
for d in items:
    s = d.get("sanitization_state", "?")
    states[s] = states.get(s, 0) + 1
print("states:", states)

print("\n=== 3. sample: download each state once ===")
seen = set()
plan = []
for d in items:
    s = d.get("sanitization_state", "?")
    if s not in seen:
        seen.add(s)
        plan.append((s, d.get("id")))
for s, did in plan:
    st, body = call(f"/api/documents/{did}/download", token=token)
    detail = ""
    if isinstance(body, dict):
        detail = str(body.get("detail") or body.get("code") or "")[:120]
    print(f"  state={s:10} download -> {st}  {detail}")

print("\n=== 4. sanitize a PENDING document (the suspected failure) ===")
pending = [d for d in items if d.get("sanitization_state") == "pending"]
if not pending:
    print("no pending documents in this matter - cannot reproduce")
else:
    did = pending[0]["id"]
    print("target:", did)
    st, v = call(f"/api/documents/{did}/verify", token=token)
    print("  verify:", st, str(v)[:160])
    st, sres = call(f"/api/documents/{did}/sanitize", {"data_level": "T3"}, token=token)
    print("  sanitize:", st, str(sres)[:300])
    st, v2 = call(f"/api/documents/{did}/verify", token=token)
    print("  verify_after:", st, str(v2)[:160])
    st, dl = call(f"/api/documents/{did}/download", token=token)
    print("  download_after:", st, str(dl)[:160])
