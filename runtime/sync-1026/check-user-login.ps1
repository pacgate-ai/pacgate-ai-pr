# Prove the path a REAL user takes: form-encoded POST (what the login page sends),
# not the JSON body my earlier probe used. That probe's 422 was my bug, not the
# service's - and I should not report a user-facing failure I created myself.
$ErrorActionPreference = 'Stop'

$py = @'
import json, os, urllib.request, urllib.error, urllib.parse

def form_login(user, pw):
    body = urllib.parse.urlencode({"username": user, "password": pw,
                                   "remember_me": "false"}).encode()
    r = urllib.request.Request("http://127.0.0.1:8001/api/v1/auth/login/local",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST")
    try:
        with urllib.request.urlopen(r, timeout=25) as x:
            return x.status, x.read().decode()[:90]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:160]

user = os.environ.get("PACGATE_API_EMAIL", "")
print("form_login_wrong_pw ->", form_login(user, "wrong-password-xyz"))
'@

$tmp = Join-Path $env:TEMP 'userlogin.py'
[System.IO.File]::WriteAllText($tmp, $py, [System.Text.UTF8Encoding]::new($false))

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & docker cp $tmp deer-flow:/tmp/userlogin.py 2>&1 | Out-Null
    & docker exec deer-flow /app/backend/.venv/bin/python /tmp/userlogin.py 2>&1 |
        Select-String -Pattern 'form_login'
}
finally { $ErrorActionPreference = $prevEap }
''
'A 401 (not 422) proves the form shape is accepted and only the password was wrong.'
'A 422 would mean users cannot log in at all.'
