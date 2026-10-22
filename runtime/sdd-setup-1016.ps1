$ErrorActionPreference = "Stop"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root

$plan = "docs\superpowers\plans\2026-10-16-capability-sync-upstream.md"
$sdd  = ".superpowers\sdd"
New-Item -ItemType Directory -Force -Path $sdd | Out-Null

$text = [System.IO.File]::ReadAllText((Join-Path $root $plan), [System.Text.Encoding]::UTF8)
$lines = $text -split "`n"

# Split on "## Task N:" headings
$tasks = @{}
$cur = $null
$buf = New-Object System.Collections.Generic.List[string]
foreach ($l in $lines) {
  if ($l -match '^## Task (\d+):') {
    if ($cur) { $tasks[$cur] = ($buf -join "`n") }
    $cur = [int]$Matches[1]
    $buf = New-Object System.Collections.Generic.List[string]
    $buf.Add($l)
  } elseif ($cur -ne $null) {
    # stop at the next top-level section that is not a task
    if ($l -match '^## (Self-Review|File Structure|Global Constraints)') { 
      $tasks[$cur] = ($buf -join "`n"); $cur = $null; $buf = New-Object System.Collections.Generic.List[string]
    } else {
      $buf.Add($l)
    }
  }
}
if ($cur) { $tasks[$cur] = ($buf -join "`n") }

foreach ($n in ($tasks.Keys | Sort-Object)) {
  $p = Join-Path $root "$sdd\task-$n-brief.md"
  [System.IO.File]::WriteAllText($p, $tasks[$n], (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ("task-$n-brief.md  (" + $tasks[$n].Length + " chars)")
}

# Ledger
$base = (git rev-parse --short HEAD)
$ledger = @"
# SDD Progress Ledger — capability sync to upstream

Plan: docs/superpowers/plans/2026-10-16-capability-sync-upstream.md
Spec: docs/superpowers/specs/2026-10-16-capability-sync-upstream-design.md
Base commit: $base

## Tasks

- [ ] Task 1: Expand connector template 3 -> 30 servers
- [ ] Task 2: Generic placeholder substitution in install.ps1
- [ ] Task 3: Add 6 connector keys to .env.example
- [ ] Task 4: Bake skills into the deer-flow image
- [ ] Task 5: Push the missing uploads-middleware patch
- [ ] Task 6: Merge PR#1 on JZKK720/deer-flow (EXTERNAL)
- [ ] Task 7: Release v0.1.32 and verify

## Minor findings (for final review triage)

(none yet)

## Log

"@
[System.IO.File]::WriteAllText((Join-Path $root "$sdd\progress.md"), $ledger, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ""
Write-Output ("ledger written, base = " + $base)
