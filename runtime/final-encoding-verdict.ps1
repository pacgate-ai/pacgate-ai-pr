$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\final-encoding-verdict.txt'

$files = @(Get-ChildItem 'c:\Users\pacga\github-pr\pacgate-law\docs\superpowers\specs' -Filter '*.md' -File -ErrorAction SilentlyContinue |
           Select-Object -ExpandProperty FullName)
$files += 'c:\Users\pacga\github-pr\pacgate-law\AGENTS.md'
$files += 'c:\Users\pacga\github-pr\pacgate-law\runtime\README.md'

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('FINAL ENCODING VERDICT (byte-level, no CJK literals in this script)')
$lines.Add('')

foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $name  = Split-Path $f -Leaf

    # 1. Strict UTF-8 validation: a decode that throws means invalid UTF-8.
    $validUtf8 = $true
    try {
        $enc = New-Object System.Text.UTF8Encoding($false, $true)   # throwOnInvalidBytes
        [void]$enc.GetString($bytes)
    } catch { $validUtf8 = $false }

    # 2. Count U+FFFD (the replacement char). Decoding corrupted bytes produces
    #    these; a clean file has none.
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $repl = 0
    foreach ($ch in $text.ToCharArray()) { if ([int][char]$ch -eq 0xFFFD) { $repl++ } }

    # 3. Has a BOM? For markdown we want none.
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

    # 4. Surrogate check, done CORRECTLY.
    #    Counting any char in U+D800..U+DFFF is a false alarm: legitimate
    #    non-BMP characters (emoji such as the warning sign) are encoded as a
    #    HIGH+ LOW surrogate PAIR, which is valid. Only UNPAIRED surrogates --
    #    a high not followed by a low, or a lone low -- indicate corruption.
    $chars = $text.ToCharArray()
    $unpaired = 0
    $paired   = 0
    for ($k = 0; $k -lt $chars.Length; $k++) {
        $c = [int][char]$chars[$k]
        if ($c -ge 0xD800 -and $c -le 0xDBFF) {
            if ($k + 1 -lt $chars.Length) {
                $nx = [int][char]$chars[$k + 1]
                if ($nx -ge 0xDC00 -and $nx -le 0xDFFF) { $paired++; $k++ }
                else { $unpaired++ }
            } else { $unpaired++ }
        } elseif ($c -ge 0xDC00 -and $c -le 0xDFFF) {
            $unpaired++
        }
    }

    $verdict = if ($validUtf8 -and $repl -eq 0 -and -not $hasBom -and $unpaired -eq 0) { 'CLEAN' } else { 'PROBLEM' }

    $lines.Add(('{0,-46} utf8={1,-6} FFFD={2,-3} BOM={3,-6} pairs={4,-3} UNPAIRED={5,-3} => {6}' -f `
        $name, $validUtf8, $repl, $hasBom, $paired, $unpaired, $verdict))
}

$lines.Add('')
$lines.Add('Note: an earlier "mojibake: True" reading came from a check whose own')
$lines.Add('CJK search pattern was corrupted by PowerShell''s GBK read of the BOM-less')
$lines.Add('script -- i.e. the test was broken, not the document. Encoding checks must')
$lines.Add('compare bytes, never CJK literals.')

[System.IO.File]::WriteAllText($out, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))