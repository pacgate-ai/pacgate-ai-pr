$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\AUTHORITATIVE-credential-status.txt'

# ============================================================================
# AUTHORITATIVE credential-tracking check.
#
# Why this script exists: comparing git paths as PowerShell STRINGS is unsafe on
# this machine. git emits UTF-8; PowerShell 5.1 decodes raw process output using
# the console codepage (GBK here), so CJK filenames become mojibake and any
# string comparison silently fails -- a false negative. That exact bug made an
# earlier scan report "not tracked" for a file that IS tracked and IS public.
#
# Therefore: compare at the BYTE level. `git ls-files -z` output is captured as
# raw bytes and searched with a byte-matcher. No string round-trip, no codepage.
# ============================================================================

$lines = New-Object System.Collections.Generic.List[string]

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

# Capture git's tracked list as RAW BYTES (no string decoding anywhere).
$tmp = 'c:\Users\pacga\github-pr\pacgate-law\runtime\_lsfiles2.raw'
& cmd /c "git -C C:\pacgate-ai-pr ls-files -z > `"$tmp`""
$raw = [System.IO.File]::ReadAllBytes($tmp)

$lines.Add("git ls-files -z raw bytes: $($raw.Length)")
$lines.Add('')

# Each filename to probe, built from code points (no CJK literals in this file).
$c   = ConvertFrom-CodePoints @(0x667A,0x5E93,0x8D44,0x6599,0x6536,0x96C6)  # 智库资料收集
$g   = ConvertFrom-CodePoints @(0x6388,0x6743)                             # 授权
$l1  = ConvertFrom-CodePoints @(0x6CD5,0x5F8B,0x6570,0x636E,0x5E93)        # 法律数据库
$l2  = ConvertFrom-CodePoints @(0x5883,0x5916,0x6CD5,0x5F8B,0x6570,0x636E,0x5E93,0x548C,0x7F51,0x7AD9) # 境外法律数据库和网站
$b1  = ConvertFrom-CodePoints @(0x767E,0x5BB8,0x41,0x49)                   # 百宸AI (prefix)

$probes = @(
    @{ Label = 'OPERATOR.md (handbook creds)';        Needle = 'pacgate-ai-remote-handbook/OPERATOR.md' },
    @{ Label = 'legal-DB passwords .md';              Needle = "MCP$g/$l1" + 'MCP.md' },
    @{ Label = 'overseas legal-DB .md';               Needle = "MCP$g/$l2.md" },
    @{ Label = 'resource inventory .docx';            Needle = "$b1" }
)

foreach ($p in $probes) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($p.Needle)
    $hits  = Find-Bytes -hay $raw -needle $bytes
    $lines.Add(('{0,-38} TRACKED={1}  (byte hits: {2})' -f $p.Label, ($hits.Count -gt 0), $hits.Count))
}

$lines.Add('')
$lines.Add('--- controls (prove the byte matcher works) ---')
foreach ($ctrl in @(@{L='OPERATOR.md positive control'; N='OPERATOR.md'}, @{L='bogus negative control'; N='zzz-not-real-9911-xyz.md'})) {
    $hb = Find-Bytes -hay $raw -needle ([System.Text.Encoding]::UTF8.GetBytes($ctrl.N))
    $lines.Add(('{0,-38} hits={1}' -f $ctrl.L, $hb.Count))
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
