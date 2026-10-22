# AIPC1 E2E chat run through deer-flow with the new default (gemma4-12b q8_0)
# Uses the verified shapes: form login (urlencode), manual Cookie header,
# thread create, langgraph-style run payload, SSE end event.
import json, re, time, urllib.request, urllib.parse, urllib.error, http.cookiejar

BASE = "http://localhost:8089"
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

# 1. login (form-encoded; deer-flow rejects JSON here)
data = urllib.parse.urlencode({"username": "admin@pacgate-law.com", "password": "a59979323b24a9356b34c8d4"}).encode()
req = urllib.request.Request(BASE + "/api/v1/auth/login/local", data=data, method="POST")
try:
    r = opener.open(req, timeout=30)
    print("login:", r.status)
except urllib.error.HTTPError as e:
    print("login FAILED:", e.code, e.read()[:200]); raise SystemExit(1)

# manual Cookie header (better-auth cookies are domain localhost.local)
cookies = "; ".join(f"{c.name}={c.value}" for c in cj)
csrf = next((c.value for c in cj if c.name == "csrf_token"), "")
hdr = {"Cookie": cookies, "X-CSRF-Token": csrf, "Content-Type": "application/json"}

# 2. create thread
req = urllib.request.Request(BASE + "/api/threads", data=json.dumps({"thread_id": None, "metadata": {}}).encode(), headers=hdr, method="POST")
r = opener.open(req, timeout=30)
tid = json.loads(r.read())["thread_id"]
print("thread:", tid)

# 3. run with explicit model selection
payload = {
    "assistant_id": "lead_agent",
    "input": {"messages": [{"type": "human", "content": [{"type": "text", "text": "Reply with exactly: FALLBACK-E2E-OK-1010"}]}]},
    "config": {"configurable": {"model_name": "gemma4-12b-local"}},
}
req = urllib.request.Request(BASE + f"/api/threads/{tid}/runs/stream", data=json.dumps(payload).encode(), headers=hdr, method="POST")
t0 = time.time()
try:
    r = opener.open(req, timeout=420)
except urllib.error.HTTPError as e:
    print("run FAILED:", e.code, e.read()[:300]); raise SystemExit(1)

end_seen = False
reply_chunks = []
buf = b""
for chunk in r:
    buf += chunk
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        s = line.decode("utf-8", "replace").strip()
        if s.startswith("event: end"):
            end_seen = True
        if s.startswith("data: ") and "FALLBACK-E2E-OK" in s:
            reply_chunks.append(s[:200])
elapsed = time.time() - t0
print(f"end_event: {end_seen}  wall: {elapsed:.1f}s")
print("reply seen:", bool(reply_chunks), reply_chunks[:1])
print("VERDICT:", "PASS" if end_seen and reply_chunks else "FAIL")
