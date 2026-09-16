$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\submodule-credential-status.txt'

# Byte-level check of the SUBMODULE (pacgate-law/pacgate-ai). The earlier
# string-based check used CJK literals and is therefore untrustworthy.
function ConvertFrom-CodePoints([int[]]$cps) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($cp in $cps) { [void]$sb.Append([char]$cp) }
    return $sb.ToString()
}
function Find-Bytes([byte[]]$hay, [byte[]]$needle) {
    $hits = New-Object System.Collections.Generic.List[int]
    if ($needle.Length -eq 0 -or $hay.Length -lt $needle.Length) { return $hits }
    for ($i = 0; $i -le ($hay.Length - $needle.Length); $i++) {
        $ok = $true
        for ($j = 0; $j -lt $needle.Length; $j++) {
            if ($hay[$i + $j] -ne $needle[$j]) { $ok = $false; break }
        }
        if ($ok) { $hits.Add($i) }
    }
    return $hits
}

$sub = 'c:\Users\pacga\github-pr\pacgate-law\pacgate-ai'
$tmp = 'c:\Users\pacga\github-pr\pacgate-law\runtime\_sub_lsfiles.raw'
& cmd /c "git -C `"$sub`" ls-files -z > `"$tmp`""
$raw = [System.IO.File]::ReadAllBytes($tmp)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('SUBMODULE credential tracking (byte-level, authoritative)')
$lines.Add("repo: $sub")
$lines.Add("tracked bytes: $($raw.Length)")
$lines.Add('')

$c  = ConvertFrom-CodePoints @(0x667A,0x5E93,0x8D44,0x6599,0x6536,0x96C6)
$g  = ConvertFrom-CodePoints @(0x6388,0x6743)
$l1 = ConvertFrom-CodePoints @(0x6CD5,0x5F8B,0x6570,0x636E,0x5E93)

$probes = @()
$probes += @{ L = 'OPERATOR.md';                 N = 'OPERATOR.md' }
$probes += @{ L = 'legal-DB passwords .md';      N = ($l1 + 'MCP.md') }
$probes += @{ L = 'assets/MCP dir present';      N = ('MCP' + $g) }

foreach ($p in $probes) {
    $hits = Find-Bytes -hay $raw -needle ([System.Text.Encoding]::UTF8.GetBytes($p.N))
    $lines.Add(('{0,-28} TRACKED={1}  (byte hits: {2})' -f $p.L, ($hits.Count -gt 0), $hits.Count))
}

$lines.Add('')
$lines.Add('--- control ---')
$ch = Find-Bytes -hay $raw -needle ([System.Text.Encoding]::UTF8.GetBytes('AGENTS.md'))
$lines.Add("AGENTS.md positive control  hits=$($ch.Count)")

$lines.Add('')
$lines.Add('--- does the submodule .gitignore name these files? ---')
if (Test-Path -LiteralPath "$sub\.gitignore") {
    $gi = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes("$sub\.gitignore"))
    $lines.Add("  .gitignore mentions OPERATOR  : $($gi -match 'OPERATOR')")
    $lines.Add("  .gitignore mentions MCP       : $($gi -match 'MCP')")
    $lines.Add("  .gitignore mentions ".Trim() + $c + " : $($gi -match [regex]::Escape($c))")
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
