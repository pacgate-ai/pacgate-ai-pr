# Live regression probe for the 0.2.5 fix:
#   "a placeholder shifted by an earlier redaction was reported as residue, so any
#    document with a phone before a card held for review with zero real leaks."
#
# The document below deliberately puts a PHONE before a CARD. Under 0.2.4 that
# ordering produced a false "residue" verdict and the document held for review.
# Under 0.2.5+ it must sanitize cleanly.
#
# Runs entirely inside the pacgate-mcp container so no host networking is needed.

$ErrorActionPreference = 'Stop'

$py = @'
import json, urllib.request, urllib.error, os, sys

BASE = "http://pacgate-api:8080"
EMAIL = os.environ["PACGATE_API_EMAIL"]
PASSWORD = os.environ["PACGATE_API_PASSWORD"]

def req(method, path, body=None, token=None, raw=None, ctype="application/json"):
    url = BASE + path
    data = None
    headers = {}
    if raw is not None:
        data = raw
        headers["Content-Type"] = ctype
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

# 1. login
st, b = req("POST", "/api/auth/login", {"email": EMAIL, "password": PASSWORD})
if st != 200:
    print("FAIL login status=%s body=%s" % (st, b[:300]))
    sys.exit(1)
token = json.loads(b)["token"]
print("PASS login")

# 2. find a matter
st, b = req("GET", "/api/matters", token=token)
if st != 200:
    print("FAIL list matters status=%s" % st)
    sys.exit(1)
matters = json.loads(b)
if isinstance(matters, dict):
    matters = matters.get("matters", matters.get("data", []))
if not matters:
    print("SKIP no matter available")
    sys.exit(2)
matter_id = matters[0]["id"]
print("PASS matter %s" % matter_id)

# 3. upload a text doc: PHONE FIRST, then CARD (the 0.2.5 regression ordering)
text = (
    "Redactor regression probe.\n"
    "Contact phone: 13812345678\n"
    "Bank card: 6222021234567890123\n"
    "Marker token: REDACTOR-025-PROBE\n"
)
boundary = "----probe025"
parts = []
parts.append(("--" + boundary + "\r\n").encode())
parts.append(b'Content-Disposition: form-data; name="matter_id"\r\n\r\n')
parts.append(matter_id.encode())
parts.append(("\r\n--" + boundary + "\r\n").encode())
parts.append(b'Content-Disposition: form-data; name="file"; filename="probe025.txt"\r\n')
parts.append(b"Content-Type: text/plain\r\n\r\n")
parts.append(text.encode("utf-8"))
parts.append(("\r\n--" + boundary + "--\r\n").encode())
payload = b"".join(parts)

st, b = req("POST", "/api/documents", token=token,
            raw=payload, ctype="multipart/form-data; boundary=" + boundary)
if st not in (200, 201):
    print("FAIL upload status=%s body=%s" % (st, b[:400]))
    sys.exit(1)
doc = json.loads(b)
doc_id = doc.get("id") or doc.get("document", {}).get("id")
print("PASS upload doc=%s" % doc_id)

# 4. sanitize at T3
st, b = req("POST", "/api/documents/%s/sanitize" % doc_id, {"data_level": "T3"}, token=token)
print("sanitize status=%s" % st)
if st != 200:
    print("FAIL sanitize body=%s" % b[:600])
    sys.exit(1)
res = json.loads(b)
verdict = res.get("verdict")
redactions = res.get("redactions", res.get("redaction_count"))
print("verdict=%s redactions=%s" % (verdict, redactions))

if verdict != "pass":
    print("FAIL verdict is %r, expected 'pass' - the 0.2.5 placeholder fix is NOT active" % verdict)
    sys.exit(1)
print("PASS verdict=pass (0.2.5 placeholder fix active)")

# 5. clean up
req("DELETE", "/api/documents/%s" % doc_id, token=token)
print("PASS cleanup")
print("RESULT: PASS")
'@

$tmp = "/tmp/probe025.py"
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($py))
docker exec pacgate-mcp sh -c "echo $b64 | base64 -d > $tmp"
docker exec pacgate-mcp python3 $tmp
exit $LASTEXITCODE
