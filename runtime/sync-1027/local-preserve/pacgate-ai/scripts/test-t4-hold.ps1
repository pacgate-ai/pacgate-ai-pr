# T4 hold proof — plan 028 §2.5
#
# The 0.2.2 release exists to enforce the T4 no-auto-pass rule. The audit could
# only assert it by reading the code, so this proves it against a running stack.
#
# Asserts, for a T4 document with a CLEAN verdict:
#   1. the sanitize response reports verdict=pass AND allow_auto_pass=false
#   2. chunks_promoted is 0
#   3. the document stays at `pending` (not `sanitized`)
#   4. download is refused (409)
#   5. kb_search does not return its chunks
# Then, for the SAME document at T3, asserts it DOES promote and DOES download.
# Step 6 is the over-correction guard: a hold that never releases is as broken
# as an auto-pass, just in the other direction.

$ErrorActionPreference = 'Stop'
$BaseUrl = 'http://localhost:8089/pacgate'
$envFile = Join-Path $PSScriptRoot '..\deploy\client-bundle\.env'
$envText = [System.IO.File]::ReadAllText((Resolve-Path $envFile))
$email = ([regex]::Match($envText, '(?m)^PACGATE_API_EMAIL=(.+)$')).Groups[1].Value.Trim()
$password = ([regex]::Match($envText, '(?m)^PACGATE_API_PASSWORD=(.+)$')).Groups[1].Value.Trim()

$passed = 0; $failed = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:passed++; Write-Host "  [PASS] $name" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  [FAIL] $name" -ForegroundColor Red; if ($detail) { Write-Host "         $detail" -ForegroundColor DarkGray } }
}

Write-Host "=== T4 hold proof (plan 028 §2.5) ===" -ForegroundColor Cyan

$login = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" -Method Post `
    -Body (@{ email = $email; password = $password } | ConvertTo-Json -Compress) `
    -ContentType 'application/json' -TimeoutSec 30
$H = @{ Authorization = "Bearer $($login.token)" }
Check 'authenticated' ([bool]$login.token)

$matter = Invoke-RestMethod -Uri "$BaseUrl/api/matters" -Method Post -Headers $H `
    -Body (@{ name = "t4-hold-$(Get-Random)" } | ConvertTo-Json -Compress) `
    -ContentType 'application/json' -TimeoutSec 30
$matterId = $matter.id
Check 'matter created' ([bool]$matterId) "matter=$matterId"

# Fixture: a born-digital PDF carrying a Tier-1 identifier so the verdict is a
# real pass-with-redactions rather than a vacuous empty document.
$fixture = Join-Path $env:TEMP 'pacgate-t4-hold.pdf'
if (Test-Path $fixture) { Remove-Item $fixture -Force }
$ocrImage = 'ghcr.io/jzkk720/ocr-service:0.2.2'
docker run --rm -v "${env:TEMP}:/fix" --entrypoint python3 $ocrImage -c "from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB',(900,300),'white')
d = ImageDraw.Draw(img)
font = ImageFont.load_default()
d.text((16,100),'11010519491231002X',fill='black',font=font)
d.text((16,150),'13812345678',fill='black',font=font)
img.save('/fix/pacgate-t4-hold.pdf','PDF',resolution=100)" 2>&1 | Out-Null
Check 'fixture written' (Test-Path $fixture)

$boundary = "----t4b$([System.Guid]::NewGuid().ToString('N'))"
$fileBytes = [System.IO.File]::ReadAllBytes($fixture)
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([System.Text.Encoding]::ASCII.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"matter_id`"`r`n`r`n$matterId`r`n--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"t4-hold.pdf`"`r`nContent-Type: application/pdf`r`n`r`n"))
$bw.Write($fileBytes)
$bw.Write([System.Text.Encoding]::ASCII.GetBytes("`r`n--$boundary--`r`n"))
$bw.Flush()
$upload = Invoke-RestMethod -Uri "$BaseUrl/api/documents" -Method Post -Headers $H `
    -ContentType "multipart/form-data; boundary=$boundary" -Body $ms.ToArray() -TimeoutSec 120
$docId = $upload.id
Check 'upload ok' ([bool]$docId) "doc=$docId"

$null = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$docId/extract" -Method Post -Headers $H `
    -ContentType 'application/json' -Body '{}' -TimeoutSec 300
Check 'extract ok' $true

# ── T4: must be held ─────────────────────────────────────────────────────────
$job = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$docId/sanitize" -Method Post -Headers $H `
    -ContentType 'application/json' -Body '{"data_level":"T4"}' -TimeoutSec 600
Check 'T4 verdict is pass' ($job.verdict -eq 'pass') "verdict=$($job.verdict)"
Check 'T4 allow_auto_pass is false' ($job.allow_auto_pass -eq $false) "allow_auto_pass=$($job.allow_auto_pass)"
Check 'T4 promoted 0 chunks' ([int]$job.chunks_promoted -eq 0) "chunks_promoted=$($job.chunks_promoted)"

$status = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$docId/sanitize-status" -Headers $H -TimeoutSec 30
Check 'T4 document stays pending' ($status.document_state -eq 'pending') "document_state=$($status.document_state)"

$dlCode = curl.exe -s -o NUL -w '%{http_code}' "$BaseUrl/api/documents/$docId/download" -H "Authorization: $($H['Authorization'])"
Check 'T4 download refused (409)' ($dlCode -eq '409') "http=$dlCode"

$search = curl.exe -s "$BaseUrl/api/kb/search?matter_id=$matterId&q=11010519491231002X" -H "Authorization: $($H['Authorization'])" | ConvertFrom-Json
$leaked = @($search | Where-Object { $_.document_id -eq $docId })
Check 'T4 chunks absent from kb_search' ($leaked.Count -eq 0) "returned $($leaked.Count) chunk(s)"

# ── T3: must release (over-correction guard) ─────────────────────────────────
$job3 = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$docId/sanitize" -Method Post -Headers $H `
    -ContentType 'application/json' -Body '{"data_level":"T3"}' -TimeoutSec 600
Check 'T3 verdict is pass' ($job3.verdict -eq 'pass') "verdict=$($job3.verdict)"
Check 'T3 allow_auto_pass is true' ($job3.allow_auto_pass -eq $true) "allow_auto_pass=$($job3.allow_auto_pass)"

$status3 = Invoke-RestMethod -Uri "$BaseUrl/api/documents/$docId/sanitize-status" -Headers $H -TimeoutSec 30
Check 'T3 document reaches sanitized' ($status3.document_state -eq 'sanitized') "document_state=$($status3.document_state)"

$dlCode3 = curl.exe -s -o NUL -w '%{http_code}' "$BaseUrl/api/documents/$docId/download" -H "Authorization: $($H['Authorization'])"
Check 'T3 download allowed (200)' ($dlCode3 -eq '200') "http=$dlCode3"

try { $null = Invoke-RestMethod -Uri "$BaseUrl/api/matters/$matterId" -Method Delete -Headers $H -TimeoutSec 30 } catch { }
Write-Host "  [cleanup] removed matter $matterId" -ForegroundColor DarkGray

Write-Host ""
if ($failed -eq 0) { Write-Host "RESULT: PASS ($passed assertions)" -ForegroundColor Green; exit 0 }
else { Write-Host "RESULT: FAIL ($passed passed, $failed failed)" -ForegroundColor Red; exit 1 }
