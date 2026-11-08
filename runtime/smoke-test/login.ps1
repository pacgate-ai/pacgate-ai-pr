# Smoke-test helper: authenticate against the real gateway.
# The gateway is mounted under /pacgate (nginx prefix), so the base URL is
# http://127.0.0.1:8089/pacgate -- not the bare host. Credentials come from
# .env by key name; nothing secret is printed.
$ErrorActionPreference = 'Stop'
$env:HTTPS_PROXY = ''; $env:HTTP_PROXY = ''; $env:https_proxy = ''; $env:http_proxy = ''

$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$envPath = Join-Path $repo 'pacgate-ai\deploy\client-bundle\.env'

$email = $null; $cred = $null
foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
    if ($line -match '^PACGATE_API_EMAIL=(.+)$')    { $email = $Matches[1].Trim() }
    if ($line -match '^PACGATE_API_PASSWORD=(.+)$') { $cred  = $Matches[1].Trim() }
}
if (-not $email -or -not $cred) { throw 'PACGATE_API_EMAIL / PACGATE_API_PASSWORD missing from .env' }

$base = 'http://127.0.0.1:8089/pacgate'
$payload = @{ email = $email; password = $cred } | ConvertTo-Json -Compress

$token = $null
foreach ($p in @("$base/api/auth/login", "$base/auth/login")) {
    try {
        $login = Invoke-RestMethod -Uri $p -Method Post -Body $payload -ContentType 'application/json' -TimeoutSec 25
        if ($login.token) { $token = $login.token; Write-Output "LOGIN_OK via $p  token_len=$($token.Length)"; break }
    } catch {
        Write-Output "  attempt $p -> HTTP $($_.Exception.Response.StatusCode.value__)"
    }
}
if (-not $token) { Write-Output 'LOGIN_FAIL'; exit 1 }
$token | Set-Content (Join-Path $repo 'runtime\smoke-test\.token') -Encoding ASCII -NoNewline
Write-Output 'TOKEN_SAVED'
