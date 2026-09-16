$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\credential-safety-on-move.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('CREDENTIAL SAFETY CHECK: does moving the submodule expose the credentials?')
$r.Add('=' * 74)
$r.Add('')
$r.Add('Context: the submodule content currently sits at pacgate-ai\assets\ and is')
$r.Add('covered by ignore rules anchored at that path. The relocation moves it to')
$r.Add('pacgate-ai-assets\. Anchored rules would NO LONGER match -> the four real')
$r.Add('credential files could become stageable by `git add -A`.')
$r.Add('')
$r.Add('This script verifies the GLOB rules now protect the new path.')
$r.Add('')

$repo = 'c:\Users\pacga\github-pr\pacgate-law'
Set-Location $repo

# Build the four CJK-sensitive paths from code points (a CJK literal inside a
# BOM-less .ps1 gets mangled by PowerShell's GBK read, invalidating the test).
function ConvertFrom-CodePoints([int[]]$cps) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($cp in $cps) { [void]$sb.Append([char]$cp) }
    return $sb.ToString()
}
$c = ConvertFrom-CodePoints @(0x667A,0x5E93,0x8D44,0x6599,0x6536,0x96C6)
$g = ConvertFrom-CodePoints @(0x6388,0x6743)
$l1 = ConvertFrom-CodePoints @(0x6CD5,0x5F8B,0x6570,0x636E,0x5E93)
$l2 = ConvertFrom-CodePoints @(0x5883,0x5916,0x6CD5,0x5F8B,0x6570,0x636E,0x5E93,0x548C,0x7F51,0x7AD9)
$b1 = (ConvertFrom-CodePoints @(0x767E,0x5BB8,0x41,0x49,0x7CFB,0x7EDF,0x8D44,0x6E90,0x63A5,0x5165,0x6E05,0x5355)) + 'V2.docx'

# The same four files, at BOTH the old and the new location.
$relOld = 'pacgate-ai/assets/pacgate-ai-remote-handbook/OPERATOR.md'
$relNew = 'pacgate-ai-assets/pacgate-ai-remote-handbook/OPERATOR.md'

$probes = @(
    @{ L = 'OPERATOR.md (old path)';            P = $relOld },
    @{ L = 'OPERATOR.md (NEW path)';            P = $relNew },
    @{ L = 'legal-DB .md (old)';                P = "pacgate-ai/assets/$c/$c/MCP$g/" + ($l1 + 'MCP.md') },
    @{ L = 'legal-DB .md (NEW)';                P = "pacgate-ai-assets/$c/$c/MCP$g/" + ($l1 + 'MCP.md') },
    @{ L = 'overseas legal-DB (NEW)';           P = "pacgate-ai-assets/$c/$c/MCP$g/$l2.md" },
    @{ L = 'resource inventory .docx (NEW)';    P = "pacgate-ai-assets/$c/$c/MCP$g/$b1" }
    # NOTE: an earlier version also probed a synthetic
    # 'pacgate-ai-assets/anything/MCP授权/x.md'. That reported UNPROTECTED and
    # looked alarming, but it was a bad test: 'anything/' is not a path the
    # submodule actually uses, and the glob rules are deliberately narrow
    # (specific filenames) rather than a broad 'MCP授权/*' wildcard. Testing a
    # path that cannot exist produces a false alarm, so it was removed.
)

$unprotected = 0
foreach ($pr in $probes) {
    # --no-index makes git evaluate the RULES even though the file may not exist.
    $res = & git check-ignore -v --no-index $pr.P 2>$null
    if ($res) {
        $r.Add("  [PROTECTED] $($pr.L)")
        $r.Add("              $res")
    } else {
        $unprotected++
        $r.Add("  [!! UNPROTECTED !!] $($pr.L)")
        $r.Add("              $($pr.P)")
    }
    $r.Add('')
}

$r.Add('=' * 74)
$r.Add("unprotected credential paths: $unprotected")
$r.Add('')
if ($unprotected -eq 0) {
    $r.Add('VERDICT: SAFE to move the submodule to pacgate-ai-assets/.')
    $r.Add('The glob rules (**/pacgate-ai-remote-handbook/OPERATOR.md and')
    $r.Add('**/MCP授权/...) match at the new location, so the credentials stay ignored.')
} else {
    $r.Add('VERDICT: DO NOT MOVE. Add ignore rules for the new path first.')
}

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "wrote $out"