$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\ALL-exposed-files-remote.txt'

function ConvertFrom-CodePoints([int[]]$cps) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($cp in $cps) { [void]$sb.Append([char]$cp) }
    return $sb.ToString()
}
$c  = ConvertFrom-CodePoints @(0x667A,0x5E93,0x8D44,0x6599,0x6536,0x96C6)
$g  = ConvertFrom-CodePoints @(0x6388,0x6743)
$l1 = ConvertFrom-CodePoints @(0x6CD5,0x5F8B,0x6570,0x636E,0x5E93)
$l2 = ConvertFrom-CodePoints @(0x5883,0x5916,0x6CD5,0x5F8B,0x6570,0x636E,0x5E93,0x548C,0x7F51,0x7AD9)
$b1 = ConvertFrom-CodePoints @(0x767E,0x5BB8,0x41,0x49,0x7CFB,0x7EDF,0x8D44,0x6E90,0x63A5,0x5165,0x6E05,0x5355,0x56,0x32) + '.docx'

$base = 'pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/'
$paths = @(
    $base + 'pacgate-ai-remote-handbook/OPERATOR.md',
    $base + "$c/$c/MCP$g/" + ($l1 + 'MCP.md'),
    $base + "$c/$c/MCP$g/$l2.md",
    $base + "$c/$c/MCP$g/$b1"
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('REMOTE EXPOSURE FOR EVERY CREDENTIAL-BEARING FILE')
$lines.Add('(negative control included so a proxy cannot fake a 200)')
$lines.Add('')

# negative control first
$bogus = 'definitely-not-real-xyz-9911/nope.md'
try {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pacgate-ai/pacgate-ai-pr/main/$bogus" -Method Head -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop | Out-Null
    $lines.Add('CONTROL bogus path            HTTP 200  <-- WARNING: proxy is faking responses')
} catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'err' }
    $lines.Add("CONTROL bogus path            HTTP $code")
}
$lines.Add('')

foreach ($p in $paths) {
    $enc = [uri]::EscapeDataString($p)
    $short = $p.Substring($p.LastIndexOf('/') + 1)

    foreach ($repo in @('pacgate-ai/pacgate-ai-pr','JZKK720/pacgate-ai-pr')) {
        try {
            $r = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$repo/main/$enc" -Method Head -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
            $lines.Add(('{0,-46} {1,-26} HTTP {2}  PUBLIC' -f $short, $repo, [int]$r.StatusCode))
        } catch {
            $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'err' }
            $lines.Add(('{0,-46} {1,-26} HTTP {2}' -f $short, $repo, $code))
        }
    }
    $lines.Add('')
}

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
