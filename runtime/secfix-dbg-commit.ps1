# Debug: fetch the base commit object from the fork and print its tree SHA.
$ErrorActionPreference = "Stop"
$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill 2>$null
$token = ($cred | Select-String "^password=").Line.Substring(9)
$h = @{ Authorization = "Bearer $token"; "User-Agent" = "pacgate-dbg"; Accept = "application/vnd.github+json" }
$sha = "bb341236cf6585980677a4952d177c05c0015cde"
try {
    $c = Invoke-RestMethod -Uri "https://api.github.com/repos/pacgate-ai/pacgate-ai-pr/git/commits/$sha" -Headers $h -TimeoutSec 30
    Write-Output "sha=$($c.sha)"
    Write-Output "tree=$($c.commit.tree.sha)"
    Write-Output "msg-first=$($c.commit.message -split "`n" | Select-Object -First 1)"
    Write-Output "parents=$($c.parents | ForEach-Object { $_.sha })"
} catch {
    Write-Output "FAIL: $($_.Exception.Message)"
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
}