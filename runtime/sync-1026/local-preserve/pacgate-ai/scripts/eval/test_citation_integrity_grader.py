#!/usr/bin/env python3
"""Self-test for the citation-integrity grader.

WHY THIS EXISTS
===============

A grader that has never been shown to FAIL is not a grader, it is a rubber
stamp. This repo already learned that lesson twice:

  - `check-tracked-file-size.ps1` silently skipped 60 of 832 files and reported
    a pass (fixed 2026-10-23);
  - `test-mcp-tool-surface.ps1` reported "1 tool advertised" because PowerShell
    5.1 collapsed a 19-element JSON array, and its four assertions failed on a
    server that was completely healthy.

Both were graders that were trusted without being mutation-tested. So this file
feeds `citation_integrity.grade()` deliberately crafted verdicts and asserts the
classification is exactly right, including the cases that must NOT be called a
pass:

    a real quote                -> VERIFIED
    a plausible but invented one -> FABRICATED
    a quote from the WRONG doc   -> FABRICATED
    a 3-character quote          -> DEGENERATE
    a quote with re-wrapped whitespace -> VERIFIED  (extraction reformats text)
    a quote differing only in full-width punctuation -> VERIFIED (NFKC)

It runs fully offline: `document_text()` is stubbed with a known body, so no
stack, no network, no model, no client data.

Run:  python scripts/eval/test_citation_integrity_grader.py
Exit: 0 all cases classified correctly, 1 a misclassification
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import citation_integrity as ci  # noqa: E402

# A stand-in for an extracted PDF. Deliberately includes CJK, full-width
# punctuation, and an internal line break, because those are the three things
# that actually differ between a model's quote and extracted text.
DOC_TEXT = """项目概况表

本项目的目标公司为上海某某科技有限公司，成立于二〇一五年三月。
甲方应于本协议签署之日起三十（30）日内支付首期款项人民币壹佰万元整。
未经乙方书面同意，甲方不得将本协议项下的任何权利义务转让给第三方。
"""

OTHER_DOC_TEXT = """劳动合同

乙方同意遵守甲方依法制定的各项规章制度。
"""

CASES: list[tuple[str, str, str, str]] = [
    # (label, quote, doc_id, expected_status)
    (
        "exact sentence",
        "甲方应于本协议签署之日起三十（30）日内支付首期款项人民币壹佰万元整",
        "doc-a",
        "VERIFIED",
    ),
    (
        "re-wrapped whitespace",
        "甲方应于本协议签署之日起三十（30）日内\n支付首期款项人民币壹佰万元整",
        "doc-a",
        "VERIFIED",
    ),
    (
        "full-width vs half-width parens",
        "甲方应于本协议签署之日起三十(30)日内支付首期款项人民币壹佰万元整",
        "doc-a",
        "VERIFIED",
    ),
    (
        "plausible but invented clause",
        "甲方应于本协议签署之日起六十（60）日内支付第二期款项人民币贰佰万元整",
        "doc-a",
        "FABRICATED",
    ),
    (
        "quote lifted from a DIFFERENT document",
        "乙方同意遵守甲方依法制定的各项规章制度",
        "doc-a",
        "FABRICATED",
    ),
    (
        "truncated real fragment, too short to prove anything",
        "项目概况",
        "doc-a",
        "DEGENERATE",
    ),
]


def main() -> int:
    doc_texts = {"doc-a": DOC_TEXT, "doc-b": OTHER_DOC_TEXT}

    # Stub the only two things that touch the outside world.
    ci.http_json = lambda url, token, method="GET", body=None, timeout=120: (  # type: ignore
        200,
        {"text": doc_texts[url.rsplit("/", 2)[-2]]},
    )

    failures = 0
    for label, quote, doc_id, expected in CASES:
        report = ci.Report()
        payload = {
            "steps": [
                {
                    "step_name": "Generate review memo",
                    "citations": [
                        {"ref_num": 1, "document_id": doc_id, "verbatim": quote}
                    ],
                }
            ]
        }
        ci.grade(payload, "http://stub", "token", report)

        if report.citations_found != 1:
            print(f"  [FAIL] {label}: expected 1 verdict, got {report.citations_found}")
            failures += 1
            continue

        got = report.verdicts[0].status
        if got == expected:
            print(f"  [PASS] {label}: {got}")
        else:
            print(f"  [FAIL] {label}: expected {expected}, got {got}")
            print(f"         detail: {report.verdicts[0].detail}")
            failures += 1

    # ── The failure-path checks. A grader that cannot report these is broken.
    print("")

    # 1. An unresolvable document must NOT be silently graded as verified.
    ci.http_json = lambda url, token, method="GET", body=None, timeout=120: (404, {})  # type: ignore
    report = ci.Report()
    ci.grade(
        {"steps": [{"step_name": "s", "citations": [
            {"ref_num": 1, "document_id": "doc-x", "verbatim": "甲方应于本协议签署之日起三十日内支付首期款项"}
        ]}]},
        "http://stub", "token", report,
    )
    if report.verdicts[0].status == "UNRESOLVABLE" and report.verified == 0:
        print("  [PASS] missing document text is UNRESOLVABLE, never VERIFIED")
    else:
        print(f"  [FAIL] missing document text graded as {report.verdicts[0].status}")
        failures += 1

    # 2. No citations at all must yield zero graded verdicts, so the caller
    #    reports CANNOT CHECK rather than PASS.
    report = ci.Report()
    ci.grade({"steps": [{"step_name": "s", "citations": []}]}, "http://stub", "token", report)
    if report.citations_found == 0:
        print("  [PASS] a run with no citations produces zero verdicts (caller reports CANNOT CHECK)")
    else:
        print(f"  [FAIL] empty citations produced {report.citations_found} verdicts")
        failures += 1

    print("")
    if failures:
        print(f"RESULT: FAIL - {failures} grader case(s) misclassified")
        return 1
    print(f"RESULT: PASS - all {len(CASES) + 2} grader cases classified correctly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
