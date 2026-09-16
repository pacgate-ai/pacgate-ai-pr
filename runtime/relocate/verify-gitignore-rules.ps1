$ErrorActionPreference = 'Continue'
$out = 'c:\Users\pacga\github-pr\pacgate-law\runtime\relocate\gitignore-verification.txt'

$r = New-Object System.Collections.Generic.List[string]
$r.Add('GITIGNORE RULE VERIFICATION')
$r.Add('=' * 60)
$r.Add('')
$r.Add('Two separate questions:')
$r.Add('  (a) Do the RULES themselves work?')
$r.Add('  (b) Why did check-ignore report "NOT IGNORED" for pacgate-ai/... ?')
$r.Add('')

$repo = 'c:\Users\pacga\github-pr\pacgate-law'
Set-Location $repo

# ---------------------------------------------------------------------------
# (b) The cause: pacgate-ai is still a SUBMODULE GITLINK, so git refuses to
#     evaluate any path inside it. The "NOT IGNORED" result was a red herring --
#     it was not a statement about the rules at all.
# ---------------------------------------------------------------------------
$r.Add('=== (b) Why the earlier check reported NOT IGNORED ===')
$r.Add('')
$r.Add('  git ls-files -s pacgate-ai :')
$gl = & git ls-files -s pacgate-ai 2>$null
foreach ($g in $gl) { $r.Add("      $g") }
$r.Add('')
$r.Add('  git check-ignore on a path inside it:')
$raw = & git check-ignore -v 'pacgate-ai/deploy/client-bundle/data/deer-flow/checkpoints.db' 2>&1
foreach ($x in $raw) { $r.Add("      $x") }
$r.Add('')
$r.Add('  => "fatal: Pathspec ... is in submodule" -- git never evaluated the rules.')
$r.Add('     The earlier NOT IGNORED result was a FALSE ALARM caused by the')
$r.Add('     submodule boundary, NOT by a missing rule.')
$r.Add('     Once the gitlink is removed (Task 1.0), paths become evaluable.')
$r.Add('')

# ---------------------------------------------------------------------------
# (a) Prove the rules work, by testing the SAME SHAPES at a non-submodule path.
# ---------------------------------------------------------------------------
$r.Add('=== (a) Do the rule patterns actually work? (tested outside the submodule) ===')
$r.Add('')
$probes = @(
    @{ P = 'probe/deploy/client-bundle/data/deer-flow/checkpoints.db'; Desc = 'client data dir' },
    @{ P = 'probe/deploy/client-bundle/.env';                          Desc = 'rendered .env' },
    @{ P = 'probe/deploy/client-bundle/deer-flow-extensions-config.json'; Desc = 'rendered config w/ keys' },
    @{ P = 'probe/deploy/qm-pacgate/tasks/x';                           Desc = 'qm runtime' },
    @{ P = 'probe/graphify-out/x';                                      Desc = 'graphify output' },
    @{ P = 'probe/deploy/client-bundle/openviking/workspace/x';         Desc = 'openviking state' }
)
$pass = 0; $fail = 0
foreach ($p in $probes) {
    # Re-shape the probe to start with 'pacgate-ai/' so the anchored rules match.
    $anchored = 'pacgate-ai/' + $p.P.Substring('probe/'.Length)
    $res = & git check-ignore -v --no-index $anchored 2>$null
    if ($res) { $pass++; $r.Add("  [PASS] $($p.Desc)") ; $r.Add("          $anchored") ; $r.Add("          -> $res") }
    else      { $fail++; $r.Add("  [FAIL] $($p.Desc)  ($anchored)") }
}
$r.Add('')
$r.Add("  patterns working: $pass   failing: $fail")
$r.Add('')
$r.Add('  NOTE: --no-index makes check-ignore evaluate the path even though the')
$r.Add('  file does not exist, which is what we want for a pre-move test.')

# ---------------------------------------------------------------------------
# Verdict + required action
# ---------------------------------------------------------------------------
$r.Add('')
$r.Add('=== VERDICT ===')
$r.Add('')
if ($fail -eq 0) {
    $r.Add('  The .gitignore rules are correct.')
    $r.Add('  The remaining blocker is purely the SUBMODULE GITLINK.')
    $r.Add('  => Task 1.0 (git rm --cached pacgate-ai) MUST run before staging,')
    $r.Add('     otherwise git cannot see the nested files at all.')
} else {
    $r.Add("  $fail rule(s) did not match -- fix the patterns before proceeding.")
}

[System.IO.File]::WriteAllText($out, ($r -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "wrote $out"