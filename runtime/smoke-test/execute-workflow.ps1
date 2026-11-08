# Smoke-test: execute one real workflow and judge whether the output is real.
# The question this answers: is a 200 from execute_workflow substantive, or is
# it a vacuous success that returns an empty/short body?
$ErrorActionPreference = 'Stop'
$env:HTTPS_PROXY = ''; $env:HTTP_PROXY = ''; $env:https_proxy = ''; $env:http_proxy = ''

$repo = 'C:\Users\pacga\github-pr\pacgate-law'
$base = 'http://127.0.0.1:8089/pacgate'
$token = (Get-Content (Join-Path $repo 'runtime\smoke-test\.token') -Raw).Trim()
$H = @{ Authorization = "Bearer $token" }

# Create a dedicated throwaway matter so the smoke test never writes into
# real firm data.
$matterName = 'smoke-wf-' + (Get-Random -Maximum 999999)
$mbody = @{ name = $matterName; description = 'workflow smoke test' } | ConvertTo-Json -Compress
$matter = Invoke-RestMethod -Uri "$base/api/matters" -Method Post -Headers $H -Body $mbody -ContentType 'application/json' -TimeoutSec 30
$matterId = $matter.id
Write-Output "MATTER=$matterId  name=$matterName"

# Pick a workflow with 2+ steps so there is something to execute.
$wfRaw = (Invoke-WebRequest "$base/api/workflows" -Headers $H -TimeoutSec 30 -UseBasicParsing).Content
$wfs = $wfRaw | ConvertFrom-Json
$wf = $wfs | Where-Object { [int]$_.step_count -ge 2 } | Select-Object -First 1
Write-Output "WORKFLOW=$($wf.id)  name=$($wf.name)  steps=$($wf.step_count)"

$body = @{ matter_id = $matterId } | ConvertTo-Json -Compress
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $resp = Invoke-WebRequest -Uri "$base/api/workflows/$($wf.id)/execute" -Method Post -Headers $H -Body $body -ContentType 'application/json' -TimeoutSec 600 -UseBasicParsing
    $sw.Stop()
    Write-Output "HTTP=$($resp.StatusCode)  elapsed=$([math]::Round($sw.Elapsed.TotalSeconds,1))s  body_len=$($resp.Content.Length)"
    $resp.Content | Set-Content (Join-Path $repo 'runtime\smoke-test\execute-response.json') -Encoding UTF8
}
catch {
    $sw.Stop()
    Write-Output "HTTP_FAIL $(@($_.Exception.Response.StatusCode.value__)) elapsed=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
    Write-Output "  $($_.Exception.Message.Split([char]10)[0])"
    exit 1
}
$matterId | Set-Content (Join-Path $repo 'runtime\smoke-test\.matter') -Encoding ASCII -NoNewline
