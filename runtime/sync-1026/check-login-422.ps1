# Are the 21 `POST /api/v1/auth/login/local` 422s a real blocker, or a probe
# sending an incomplete body? Reproduce the call with a deliberately bad payload
# and with a good one, and compare.
$ErrorActionPreference = 'Stop'

'=== 422 timestamps (when did they happen?) ==='
$logFile = Join-Path $env:TEMP 'deerflow-gateway.log'
$lines = Get-Content $logFile
$lines | Select-String -Pattern 'login/local.*422' -Context 0,0 | Measure-Object | ForEach-Object {
    "count=$($_.Count)"
}

'=== does the endpoint reject an EMPTY body (expected 422)? ==='
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $script = @'
import json, urllib.request, urllib.error
def post(body):
    r = urllib.request.Request("http://127.0.0.1:8001/api/v1/auth/login/local",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(r, timeout=20) as x:
            return x.status, x.read().decode()[:160]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:220]
print("empty_body      ->", post({}))
print("missing_password->", post({"email": "x@y.z"}))
print("with_creds      ->", post({"email": "no-such-user@example.com", "password": "wrong"}))
'@
    $tmp = Join-Path $env:TEMP 'loginprobe.py'
    [System.IO.File]::WriteAllText($tmp, $script, [System.Text.UTF8Encoding]::new($false))
    & docker cp $tmp deer-flow:/tmp/loginprobe.py 2>&1 | Out-Null
    & docker exec deer-flow /app/backend/.venv/bin/python /tmp/loginprobe.py 2>&1
}
finally { $ErrorActionPreference = $prevEap }
