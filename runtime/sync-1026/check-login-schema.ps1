# 21 real `POST /api/v1/auth/login/local` 422s appeared in the gateway log.
# Find the endpoint's actual request schema, so we can say whether the caller or
# the service is wrong. (A 422 on a login form is a caller-shape bug until proven
# otherwise, but "proven" means reading the schema, not guessing.)
$ErrorActionPreference = 'Stop'

$py = @'
import json, urllib.request, os
# The gateway's OpenAPI is not public, but the login route is registered by a
# bind-mounted patch. Ask the running app for its own schema instead of guessing.
import sys
sys.path.insert(0, "/app/backend")
try:
    from app.gateway.routers.auth import LoginRequest
    print("LoginRequest fields:", list(getattr(LoginRequest, "model_fields", {}).keys()))
except Exception as e:
    print("import failed:", type(e).__name__, e)
'@

$tmp = Join-Path $env:TEMP 'loginschema.py'
[System.IO.File]::WriteAllText($tmp, $py, [System.Text.UTF8Encoding]::new($false))

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & docker exec pacgate-api sh -c 'true' 2>&1 | Out-Null
    & docker cp $tmp deer-flow:/tmp/loginschema.py 2>&1 | Out-Null
    & docker exec deer-flow /app/backend/.venv/bin/python /tmp/loginschema.py 2>&1 |
        Select-String -Pattern 'LoginRequest|import failed'
}
finally { $ErrorActionPreference = $prevEap }

''
'=== the route definition in the mounted auth patch ==='
$p = 'C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\patches\deer-flow-auth.py'
Select-String -Path $p -Pattern 'login/local|class .*Login|username|email.*str' |
    Select-Object -First 20 | ForEach-Object { '  {0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
