import sys

sys.path.insert(0, "packages/harness")
from deerflow.skills.tool_policy import _tool_matches_declaration

cases = [
    ("pkulaw_law_search", "pkulaw", True),
    ("yuandian_law_search", "yuandian-law", True),
    ("pacgate_pacgate_list_matters", "pacgate", True),
    ("bash", "bash", True),
    ("unrelated_tool", "pkulaw", False),
]
ok = 0
for tool, decl, expected in cases:
    got = _tool_matches_declaration(tool, decl)
    status = "OK" if got == expected else "FAIL"
    if got == expected:
        ok += 1
    print(f"[{status}] {tool} vs {decl}: {got}")
print(f"{ok}/{len(cases)} prefix-matching cases pass")
