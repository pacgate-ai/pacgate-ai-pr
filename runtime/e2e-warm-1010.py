# Warm-path test: second run on the SAME thread (prompt cache should kick in)
import json, time, urllib.request, urllib.parse, urllib.error, http.cookiejar

BASE = "http://localhost:8089"
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
data = urllib.parse.urlencode({"username": "admin@pacgate-law.com", "password": "a59979323b24a9356b34c8d4"}).encode()
req = urllib.request.Request(BASE + "/api/v1/auth/login/local", data=data, method="POST")
r = opener.open(req, timeout=30)
cookies = "; ".join(f"{c.name}={c.value}" for c in cj)
csrf = next((c.value for c in cj if c.name == "csrf_token"), "")
hdr = {"Cookie": cookies, "X-CSRF-Token": csrf, "Content-Type": "application/json"}

# reuse the thread from the first E2E run
TID = "fc3eb0b5-067a-4dc7-a313-bd743f003be3"
payload = {
    "assistant_id": "lead_agent",
    "input": {"messages": [{"type": "human", "content": [{"type": "text", "text": "Reply with exactly: WARM-PATH-OK"}]}]},
    "config": {"configurable": {"model_name": "gemma4-12b-local"}},
}
req = urllib.request.Request(BASE + f"/api/threads/{TID}/runs/stream", data=json.dumps(payload).encode(), headers=hdr, method="POST")
t0 = time.time()
try:
    r = opener.open(req, timeout=420)
except urllib.error.HTTPError as e:
    print("run FAILED:", e.code, e.read()[:300]); raise SystemExit(1)
end_seen = False
buf = b""
for chunk in r:
    buf += chunk
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        s = line.decode("utf-8", "replace").strip()
        if s.startswith("event: end"):
            end_seen = True
elapsed = time.time() - t0
print(f"end_event: {end_seen}  wall: {elapsed:.1f}s")
print("VERDICT:", "PASS" if end_seen else "FAIL")
