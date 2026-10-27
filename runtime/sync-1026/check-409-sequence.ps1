# Show the exact request sequence for one document that 409'd, to see whether the
# agent recovered (sanitize -> 200 -> download 200) or looped on the 409.
$ErrorActionPreference = 'Stop'
$mcpLog = Join-Path $env:TEMP 'pacgate-mcp.log'
$lines = Get-Content $mcpLog

$docs = @('b3272709-f62e-4973-864d-801eed377bb3', 'de7027a9-7d14-4c4d-a235-63beb8aa1b24')

foreach ($d in $docs) {
    "===== $d ====="
    $lines | Select-String -Pattern $d | ForEach-Object {
        $t = $_.Line.Trim()
        # Keep only the method/path/status tail, not the whole log prefix.
        if ($t -match '(GET|POST) [^ ]*documents/[^ ]*/(download|sanitize|sanitize-status)[^"]*"\s*(HTTP/[0-9.]+ )?(\d{3})') {
            '  {0,-16} {1}' -f $Matches[2].ToUpper(), ($Matches[1] + ' -> ' + $Matches[4])
        }
        elseif ($t -match '(GET|POST) [^ ]*documents/[^ ]*/(download|sanitize|sanitize-status)') {
            '  ' + $Matches[2].ToUpper() + ' (status not on this line)'
        }
    }
    ''
}

'=== tally of document sub-route outcomes ==='
$lines | ForEach-Object {
    if ($_ -match 'documents/[^ ]*/(download|sanitize|sanitize-status)[^"]*"\s*(?:HTTP/[0-9.]+ )?(\d{3})') {
        '{0} {1}' -f $Matches[1], $Matches[2]
    }
} | Group-Object | Sort-Object Count -Descending | ForEach-Object { '  {0,4}  {1}' -f $_.Count, $_.Name }
