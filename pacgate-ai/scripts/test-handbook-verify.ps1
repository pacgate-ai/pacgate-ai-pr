# Verbatim copy of the verify snippet now in deploy/AIPC-DEPLOYMENT-HANDBOOK.md
# Run this to prove the handbook instruction actually works.
$acc = "application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json"
# Anchor to the script's own repo root. As a bare relative path this resolved
# against the CALLER's cwd, so running the gate from anywhere else produced zero
# pins and still exited 0 -- a vacuous green on a check that verified nothing.
$compose = Join-Path (Split-Path -Parent $PSScriptRoot) "deploy/client-bundle/compose.prod.yaml"
if (-not (Test-Path -LiteralPath $compose)) {
    throw "handbook verify: compose file not found at $compose"
}
$pins = Select-String -Path $compose -Pattern "image:\s*(ghcr\.io/[^\s]+)" -AllMatches |
        ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -notmatch "openviking" } | Sort-Object -Unique

$bad = 0
foreach ($pin in $pins) {
  $repo = $pin -replace "^ghcr\.io/", ""
  $name = ($repo -split ":")[0]
  $tag  = ($repo -split ":")[1]
  try {
    $t = (Invoke-RestMethod "https://ghcr.io/token?scope=repository:$name`:pull").token
    $code = (Invoke-WebRequest -Uri "https://ghcr.io/v2/$name/manifests/$tag" -Headers @{Authorization="Bearer $t"; Accept=$acc} -Method Head -UseBasicParsing).StatusCode
  } catch {
    $code = $_.Exception.Response.StatusCode.value__
    if (-not $code) { $code = "ERR" }
  }
  "{0,-58} => HTTP {1}" -f $pin, $code
  if ($code -ne 200) { $bad++ }
}
if (-not $pins -or $pins.Count -eq 0) {
  throw "handbook verify: 0 pins resolved - refusing to report success on an empty check"
}
if ($bad -gt 0) {
  throw "handbook verify: $bad of $($pins.Count) pins did not return HTTP 200"
}
"RESULT: all $($pins.Count) pins resolve to HTTP 200."
