# Confirm the /api/v1/auth/login/local shape: `username`, not `email`.
$ErrorActionPreference = 'Stop'

$py = @'
import json, os, urllib.request, urllib.error

def post(body):
    r = urllib.request.Request("http://127.0.0.1:8001/api/v1/auth/login/local",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(r, timeout=20) as x:
            return x.status, x.read().decode()[:100]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]

user = os.environ.get("PACGATE_API_EMAIL", "")
print("email_field   ->", post({"email": user, "password": "x"}))
print("username_field->", post({"username": user, "password": "definitely-wrong-pw"}))
'@

$tmp = Join-Path $env:TEMP 'loginprobe2.py'
[System.IO.File]::WriteAllText($tmp, $py, [System.Text.UTF8Encoding]::new($false))

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & docker cp $tmp deer-flow:/tmp/loginprobe2.py 2>&1 | Out-Null
    & docker exec deer-flow /app/backend/.venv/bin/python /tmp/loginprobe2.py 2>&1 |
        Select-String -Pattern 'field'
}
finally { $ErrorActionPreference = $prevEap }
