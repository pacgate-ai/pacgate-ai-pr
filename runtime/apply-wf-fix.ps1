$ErrorActionPreference = 'Stop'
$path = 'C:\pacgate-ai-pr\.github\workflows\build-ghcr.yml'
$bytes = [System.IO.File]::ReadAllBytes($path)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)

$anchor = "          git -C deploy/deer-flow-src sparse-checkout set frontend`n`n      - name: Build & push deer-flow-frontend-pacgate"
$insert = "          git -C deploy/deer-flow-src sparse-checkout set frontend`n`n      # Apply the PacGate frontend source overrides (branded UI, zh-CN strings,`n      # thread hooks). build-frontend.ps1 does this locally; CI must do the`n      # same or the published image silently loses the PacGate customizations.`n      # Files are copied (not git-patched) because they contain long Chinese`n      # strings that break git-patch parsing - same mechanism as the local script.`n      # Verified 2026-09-17: published 0.1.14 had 0 pacgate-marked files in`n      # .next vs 9 in the locally-built image - this step closes that gap.`n      - name: Apply PacGate frontend source overrides`n        run: |`n          if [ ! -d deploy/frontend-patches/files ]; then`n            echo `"ERROR: deploy/frontend-patches/files missing from checkout`" && exit 1`n          fi`n          cp -rv deploy/frontend-patches/files/. deploy/deer-flow-src/frontend/`n`n      - name: Build & push deer-flow-frontend-pacgate"

if ($text.Contains($anchor)) {
  $new = $text.Replace($anchor, $insert)
  [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::UTF8.GetBytes($new))
  Write-Output "EDIT APPLIED"
} else {
  # try CRLF variant
  $anchorCRLF = $anchor -replace "`n", "`r`n"
  $insertCRLF = $insert -replace "`n", "`r`n"
  if ($text.Contains($anchorCRLF)) {
    $new = $text.Replace($anchorCRLF, $insertCRLF)
    [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::UTF8.GetBytes($new))
    Write-Output "EDIT APPLIED (CRLF)"
  } else {
    Write-Output "ANCHOR NOT FOUND"
  }
}
# verify
$check = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($path))
Write-Output "contains 'Apply PacGate': $($check.Contains('Apply PacGate'))"