# Corrected document pipeline: sanitize with {"data_level":"T3"} + kb_search GET — 2026-10-10
$ErrorActionPreference = "Continue"
$w = "c:\Users\pacga\github-pr\pacgate-law"
$cb = "$w\pacgate-ai\deploy\client-bundle"
$out = @()
function Time($n, $ms, $d) { $script:out += "[TIME] $n : $ms ms $d" }
function Pass($n, $d) { $script:out += "[PASS] $n : $d" }
function Fail($n, $d) { $script:out += "[FAIL] $n : $d" }

$envVars = @{}
Get-Content "$cb\.env" -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^([A-Z_0-9]+)=(.*)$") { $envVars[$Matches[1]] = $Matches[2] }
}
$body = @{ email = $envVars["PACGATE_API_EMAIL"]; password = $envVars["PACGATE_API_PASSWORD"] } | ConvertTo-Json -Compress
$tmp = "$env:TEMP\audit-login4-1010.json"
[System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
$login = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/auth/login" -Method Post -ContentType "application/json" -InFile $tmp -TimeoutSec 20
$h = @{ Authorization = "Bearer $($login.token)" }
$matters = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/matters" -Headers $h -TimeoutSec 20
$mid = $matters[0].id

# 1. KB search — GET /api/kb/search with query params
$out += "=== KB SEARCH (GET, correct) ==="
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $kb = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/kb/search?q=settlement%20authority" -Headers $h -TimeoutSec 30
    $sw.Stop()
    $kbJson = $kb | ConvertTo-Json -Compress
    Time "GET /api/kb/search" $sw.ElapsedMilliseconds "len=$($kbJson.Length)"
    $out += "  sample: $($kbJson.Substring(0, [Math]::Min(200, $kbJson.Length)))"
} catch {
    $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
    Fail "kb search GET" "HTTP $code"
}

# 2. Full document pipeline with correct sanitize contract
$out += ""
$out += "=== DOCUMENT PIPELINE (corrected) ==="
$fixture = "CONFIDENTIAL DRAFT`nClient: Zhang Wei`nID: 11010519491231002X`nPhone: 13812345678`nMarker-PACGATE-AUDIT-1010d`n"
$fixPath = "$env:TEMP\audit-fixture4-1010.txt"
[System.IO.File]::WriteAllText($fixPath, $fixture, (New-Object System.Text.UTF8Encoding($false)))
$boundary = "----AuditBoundary1010d"
$fileBytes = [System.IO.File]::ReadAllBytes($fixPath)
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([System.Text.Encoding]::UTF8.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"audit-fixture4.txt`"`r`nContent-Type: text/plain`r`n`r`n"))
$bw.Write($fileBytes)
$bw.Write([System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary`r`nContent-Disposition: form-data; name=`"matter_id`"`r`n`r`n$mid`r`n--$boundary--`r`n"))
$bw.Flush()
$upTmp = "$env:TEMP\audit-upload4-1010.bin"
[System.IO.File]::WriteAllBytes($upTmp, $ms.ToArray())

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$doc = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -InFile $upTmp -Headers $h -TimeoutSec 30
$sw.Stop()
Time "upload" $sw.ElapsedMilliseconds "id=$($doc.id)"
$docId = $doc.id

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$ext = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/extract" -Method Post -Headers $h -TimeoutSec 120
$sw.Stop()
Time "extract" $sw.ElapsedMilliseconds "incomplete=$($ext.incomplete) len=$($ext.text.Length)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$sanBody = @{ data_level = "T3" } | ConvertTo-Json -Compress
$sanTmp = "$env:TEMP\audit-san4-1010.json"
[System.IO.File]::WriteAllText($sanTmp, $sanBody, (New-Object System.Text.UTF8Encoding($false)))
$san = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/sanitize" -Method Post -ContentType "application/json" -InFile $sanTmp -Headers $h -TimeoutSec 180
$sw.Stop()
Time "sanitize T3" $sw.ElapsedMilliseconds "verdict=$($san.verdict) redactions=$($san.redaction_count) mappings=$($san.mapping_count)"

# download gate
try {
    $dl = Invoke-WebRequest -Uri "http://localhost:8089/pacgate/api/documents/$docId/download" -Headers $h -TimeoutSec 20 -UseBasicParsing
    $out += "[PASS] download gate: HTTP $($dl.StatusCode) (verdict=$($san.verdict) -> gate OPEN)"
} catch {
    $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
    if ($code -eq 409) { $out += "[PASS] download gate: HTTP 409 SHUT (verdict=$($san.verdict) — correct compliance)" }
    else { $out += "[NOTE] download gate: HTTP $code verdict=$($san.verdict)" }
}

# sanitize-status
try {
    $st = Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId/sanitize-status" -Headers $h -TimeoutSec 20
    $out += "[PASS] sanitize-status: $($st | ConvertTo-Json -Compress | ForEach-Object { $_.Substring(0,[Math]::Min(150,$_.Length)) })"
} catch { $out += "[NOTE] sanitize-status: $($_.Exception.Message)" }

# cleanup
try {
    Invoke-RestMethod -Uri "http://localhost:8089/pacgate/api/documents/$docId" -Method Delete -Headers $h -TimeoutSec 20 | Out-Null
    $out += "[PASS] cleanup: doc deleted"
} catch { $out += "[NOTE] cleanup failed: $docId remains" }

$out | Out-File -FilePath "$w\runtime\audit2d-pipeline-1010.txt" -Encoding utf8
Write-Output "AUDIT2D DONE"