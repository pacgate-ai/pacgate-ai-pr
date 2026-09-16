$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\exposure-control-results.txt'

$rel   = 'pacgate-ai/pacgate-ai-assets/pacgate-ai/assets/assets/pacgate-ai-remote-handbook/OPERATOR.md'
$bogus = 'definitely-not-a-real-path-xyz123/does-not-exist-abc987.md'

# A control test guards against false positives. If a corporate proxy or VPN
# intercepts requests and answers 200 for everything, then a 200 on the target
# file would be meaningless. A path that canonicaly cannot exist must 404.
$tests = @(
    @{ Label = 'CONTROL: bogus path (must 404)';  Url = "https://raw.githubusercontent.com/pacgate-ai/pacgate-ai-pr/main/$bogus";        Kind = 'control' },
    @{ Label = 'CONTROL: bogus repo (must 404)';  Url = "https://raw.githubusercontent.com/pacgate-ai/zzz-no-such-repo-xyz/main/README.md"; Kind = 'control' },
    @{ Label = 'TARGET: fork raw';                Url = "https://raw.githubusercontent.com/pacgate-ai/pacgate-ai-pr/main/$rel";          Kind = 'target' },
    @{ Label = 'TARGET: origin raw';              Url = "https://raw.githubusercontent.com/JZKK720/pacgate-ai-pr/main/$rel";            Kind = 'target' }
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('EXPOSURE CHECK WITH NEGATIVE CONTROLS')
$lines.Add('')

foreach ($t in $tests) {
    try {
        $r = Invoke-WebRequest -Uri $t.Url -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
        $len = 0
        if ($r.Content) { $len = $r.Content.Length }
        $lines.Add(('{0,-34} HTTP {1}  bytes={2}' -f $t.Label, [int]$r.StatusCode, $len))
    } catch {
        $code = 'n/a'
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        $lines.Add(('{0,-34} HTTP {1}' -f $t.Label, $code))
    }
}

$lines.Add('')
$lines.Add('Interpretation:')
$lines.Add('  If the CONTROL rows return 404 and the TARGET rows return 200, the')
$lines.Add('  200 responses are genuine and the file is publicly readable.')
$lines.Add('  If the CONTROL rows also return 200, the responses are being')
$lines.Add('  intercepted (proxy) and this test proves nothing.')

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
