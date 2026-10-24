#!/usr/bin/env python3
"""Self-test for the answer-substance eval's matching rules.

WHY THIS EXISTS
===============

`answer_substance.py` compares planted fact values against the model's output
using `citation_integrity.norm()` - NFKC + whitespace-stripped, lowercased. That
normalisation is deliberately permissive so a real value wrapped across a line
still matches. The risk of a permissive matcher is a FALSE GREEN: a short value
matching inside unrelated text.

The planted facts include two short ones, `45` and `20%`. A naive substring test
for `45` would match "45" inside "450", "145", or a document id, and would
report PASS on an output that never mentioned the payment term. That is exactly
the class of defect this repo has shipped twice, so the matcher's behaviour is
pinned here rather than assumed.

Run:  python scripts/eval/test_answer_substance_matching.py
Exit: 0 all cases classified correctly, 1 a misclassification
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import citation_integrity as ci  # noqa: E402
import answer_substance as sub  # noqa: E402

# (label, produced_output, planted_value, should_match)
CASES: list[tuple[str, str, str, bool]] = [
    (
        "exact monetary value",
        "本次股权转让总价款为人民币肆仟捌佰万元整（RMB 48,000,000.00），分两期支付。",
        "RMB 48,000,000.00",
        True,
    ),
    (
        "value wrapped across a newline by the model",
        "总价款为人民币肆仟捌佰万元整\n（RMB 48,000,000.00）。",
        "RMB 48,000,000.00",
        True,
    ),
    (
        "value never mentioned",
        "本协议的主要风险在于违约责任条款过于笼统。",
        "RMB 48,000,000.00",
        False,
    ),
    (
        "percentage present",
        "转让方持有目标公司百分之十二点五（12.5%）的股权。",
        "12.5%",
        True,
    ),
    (
        "percentage absent, a DIFFERENT one present",
        "转让方持有目标公司百分之二十五（25%）的股权。",
        "12.5%",
        False,
    ),
    (
        "short numeric fact inside a longer number (the false-green case)",
        "本次交易的登记编号为 9145010000，与付款期限无关。",
        "45",
        False,
    ),
    (
        "short numeric fact stated on its own",
        "受让方应于本协议生效之日起四十五（45）个自然日内支付。",
        "45",
        True,
    ),
    (
        "full-width parens around the percentage",
        "转让方持有目标公司百分之十二点五(12.5%)的股权。",
        "12.5%",
        True,
    ),
    (
        "arbitration body with an internal space from extraction",
        "可向上海国际经济贸易仲裁委员 会提起仲裁。",
        "上海国际经济贸易仲裁委员会",
        True,
    ),
]


def main() -> int:
    failures = 0
    for label, produced, planted, expected in CASES:
        got = sub.fact_present(planted, ci.norm(produced))
        if got == expected:
            print(f"  [PASS] {label}: matched={got}")
        else:
            print(f"  [FAIL] {label}: expected matched={expected}, got {got}")
            print(f"         planted={planted!r} produced={produced!r}")
            failures += 1

    # ── The digit-boundary rule is the fix; prove it actually discriminates ──
    #
    # Before 2026-10-24 this eval used a plain substring test and a bare `45`
    # matched inside `450` AND inside a 10-digit registration number. Both are
    # asserted here so a regression to plain containment is caught.
    print("")
    boundary_cases = [
        ("inside 450", "共计 450 万元", "45", False),
        ("inside a registration number", "登记编号 9145010000", "45", False),
        ("standalone", "逾期 45 日", "45", True),
        ("as a word", "共 45 项", "45", True),
    ]
    for label, produced, planted, expected in boundary_cases:
        got = sub.fact_present(planted, ci.norm(produced))
        if got == expected:
            print(f"  [PASS] digit boundary, {label}: matched={got}")
        else:
            print(f"  [FAIL] digit boundary, {label}: expected {expected}, got {got}")
            failures += 1

    print("")
    if failures:
        print(f"RESULT: FAIL - {failures} matching case(s) misclassified")
        return 1
    print(f"RESULT: PASS - all {len(CASES) + len(boundary_cases)} matching cases behave as documented")
    return 0


if __name__ == "__main__":
    sys.exit(main())
