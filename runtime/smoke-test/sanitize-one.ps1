# Smoke-test: how long does ONE sanitizer job take, and does the time scale with
# document size? "Is the sanitizer batch too long" is an empirical question --
# this measures real runs rather than guessing from the code.
#
# POST /api/documents/:id/sanitize requires {"data_level":"T1|T2|T3|T4"}.
$ErrorActionPreference = 'Stop'
$env:HTTPS_PROXY = ''; $env:HTTP_PROXY = ''; $env:https_proxy = ''; $env:http_proxy = ''

$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$base = 'http://127.0.0.1:8089/pacgate'
$token = (Get-Content (Join-Path $repo 'runtime\smoke-test\.token') -Raw).Trim()
$H = @{ Authorization = "Bearer $token" }

$docId = $args[0]
if (-not $docId) { $docId = '08735c83-35c7-496c-94fd-59f613dc491d' }
$level = if ($args[1]) { $args[1] } else { 'T2' }

$body = @{ data_level = $level } | ConvertTo-Json -Compress
Write-Output "DOC=$docId  data_level=$level"

$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $r = Invoke-WebRequest -Uri "$base/api/documents/$docId/sanitize" -Method Post -Headers $H `
        -ContentType 'application/json' -Body $body -TimeoutSec 900 -UseBasicParsing
    $sw.Stop()
    Write-Output "  HTTP=$($r.StatusCode)  elapsed=$([math]::Round($sw.Elapsed.TotalSeconds,2))s"
    Write-Output "  body: $($r.Content)"
    $r.Content | Set-Content (Join-Path $repo 'runtime\smoke-test\sanitize-response.json') -Encoding UTF8
}
catch {
    $sw.Stop()
    Write-Output "  FAIL HTTP=$($_.Exception.Response.StatusCode.value__) elapsed=$([math]::Round($sw.Elapsed.TotalSeconds,2))s"
    Write-Output "  err: $($_.Exception.Message.Split([char]10)[0])"
}
