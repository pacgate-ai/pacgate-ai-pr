$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\install-mechanics.txt'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('INSTALL / FIRST-RUN MECHANICS (what a complete deliverable must contain)')
$lines.Add('')

# ---------- 1. How is compose invoked? (does the project name get pinned?) ----------
$lines.Add('=== 1. Compose invocations found in scripts ===')
$scripts = @(
    'C:\pacgate-ai-pr\deploy\client-bundle\install.ps1',
    'C:\pacgate-ai-pr\deploy\client-bundle\setup-qm.ps1',
    'C:\pacgate-ai-pr\deploy\client-bundle\smoke-deer-flow-outputs.ps1',
    'C:\pacgate-ai-pr\deploy\build-images.ps1'
)
foreach ($s in $scripts) {
    if (-not (Test-Path -LiteralPath $s)) { continue }
    $lines.Add("  --- $(Split-Path $s -Leaf) ---")
    $i = 0
    foreach ($ln in [System.IO.File]::ReadAllLines($s)) {
        $i++
        if ($ln -match 'docker compose|docker-compose|-p\s|--project-name|-f\s.*compose|Set-Location|Push-Location|cd ') {
            $t = $ln.Trim()
            if ($t.Length -gt 150) { $t = $t.Substring(0,150) + '...' }
            $lines.Add(('      L{0,-4} {1}' -f $i, $t))
        }
    }
    $lines.Add('')
}

# ---------- 2. Does first run CREATE the state dirs, or expect them present? ----------
$lines.Add('=== 2. Does install create state dirs (or does the repo ship them)? ===')
foreach ($s in $scripts) {
    if (-not (Test-Path -LiteralPath $s)) { continue }
    $lines.Add("  --- $(Split-Path $s -Leaf) ---")
    $i = 0
    foreach ($ln in [System.IO.File]::ReadAllLines($s)) {
        $i++
        if ($ln -match 'New-Item|mkdir|MD \b|Copy-Item|\.env|readyaml|template') {
            $t = $ln.Trim()
            if ($t.Length -gt 140) { $t = $t.Substring(0,140) + '...' }
            $lines.Add(('      L{0,-4} {1}' -f $i, $t))
        }
    }
    $lines.Add('')
}

# ---------- 3. Which config files are templates (shipped) vs real (runtime)? ----------
$lines.Add('=== 3. Template vs live config in client-bundle ===')
$cb = 'C:\pacgate-ai-pr\deploy\client-bundle'
foreach ($f in (Get-ChildItem -LiteralPath $cb -File -Force -ErrorAction SilentlyContinue)) {
    $kind = 'shipped? '
    $rel = $f.FullName.Replace('C:\pacgate-ai-pr\','').Replace('\','/')
    $chk = & git -C C:\pacgate-ai-pr check-ignore -- $rel 2>$null
    if ($chk) { $kind = 'IGNORED  ' } else { $kind = 'TRACKED  ' }
    $lines.Add(('  {0} {1,-46} {2} bytes' -f $kind, $f.Name, $f.Length))
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
