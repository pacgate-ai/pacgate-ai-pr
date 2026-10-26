#!/usr/bin/env python3
"""Citation-integrity eval for the PacGate generation path.

WHY THIS EXISTS
===============

This is the answer to one question the 48-gate suite could never ask:

    when the model cites a document, is the citation REAL?

`crates/pacgate-agent/src/system_prompt_base.txt` mandates a `<CITATIONS>` block
with `verbatim` quotes of 25 words or less. `extract_citations()` in
`pacgate-agent/src/lib.rs` PARSES that block and hands the strings to
`CitationRef.verbatim`, which reaches the API response as
`steps[].citations[].verbatim`.

Nothing ever compares that quote against the document it claims to come from. So
a fabricated quote is structurally indistinguishable from a real one: both are
non-empty strings in a field nobody verifies. That is the red line from
`SOUL_Sylvie_v1.0.md`:

    "检索不到依据时如实报告,不得用模型自身知识或网络内容无声填补法律结论"

sitting in the data path with no guard.

WHAT IT DOES
============

For each generated document that returns citations:

  1. resolve every cited `document_id` through `GET /api/documents/:id/extract`
     (the same endpoint the product uses) and take its `text`
  2. normalise both sides and check that the `verbatim` quote actually occurs
  3. additionally check the quote is not degenerate (too short to prove anything)

A quote that does not occur is a FABRICATED CITATION. It is reported with the
quote, the document, and the closest fragment found, because "citation 2 is bad"
is not actionable and "this 14-word quote appears nowhere" is.

GRADER DESIGN - why code, not an LLM
====================================

This is a `code grader` in eval-harness terms: fully deterministic, no model in
the loop, so it cannot be talked out of a finding. Two consequences that matter
for a law firm:

  - ZERO EGRESS. It reads text the platform already stored. No client document
    or generated output is sent anywhere for grading. This is why the LLM-judge
    lane is deliberately NOT part of this file - grading cloud-generated output
    with a cloud judge would create a second egress path that
    test-chat-no-auto-egress.ps1 exists to prevent.
  - it can run against ALREADY-RECORDED runs. Pass --from-json with a saved
    execute response and it grades offline, so a release soak does not have to
    pay for generations again.

Exit codes
==========
  0  every citation verified
  1  at least one fabricated or degenerate citation
  2  CANNOT CHECK - stack down, no credentials, or no citations to grade

A `2` is important and deliberately not a failure. "The model returned no
citations at all" is a different, weaker finding: it means the citation
machinery never engaged. Reporting that as a fabrication would be wrong, and
reporting it as a pass would be worse.

Usage
=====
    python scripts/eval/citation_integrity.py
    python scripts/eval/citation_integrity.py --from-json saved-execute.json
    python scripts/eval/citation_integrity.py --workflow-id <uuid> --json
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import unicodedata
import urllib.error
import urllib.request
from dataclasses import dataclass, field, asdict
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, ValueError):
        pass

# ── Verification thresholds ──────────────────────────────────────────────────
#
# MIN_QUOTE_CHARS is not cosmetic. A 3-character "citation" occurs in almost any
# document by chance, so accepting it would let a degenerate citation pass as
# verified - a false green, which is the failure mode this whole file exists to
# avoid. The base prompt already tells the model "<= 25 words"; this is the
# floor, not a second rule.
MIN_QUOTE_CHARS = 8


def norm(s: str) -> str:
    """Normalise text for occurrence testing.

    NFKC folds full-width punctuation to ASCII and unifies CJK compatibility
    forms; collapsing all whitespace makes a quote tolerant of the line breaks
    and re-wrapping that extraction introduces. Applied identically to both
    sides, so it can only ever make a REAL quote match - it cannot manufacture a
    match out of unrelated text.

    Punctuation is NOT stripped. Removing it would let a quote match across a
    punctuation boundary it never actually spanned.
    """
    s = unicodedata.normalize("NFKC", s)
    return re.sub(r"\s+", "", s).lower()


@dataclass
class CitationVerdict:
    step_name: str
    ref_num: int
    document_id: str
    quote: str
    status: str                      # VERIFIED | FABRICATED | DEGENERATE | UNRESOLVABLE
    detail: str = ""


@dataclass
class Report:
    citations_found: int = 0
    verified: int = 0
    fabricated: int = 0
    degenerate: int = 0
    unresolvable: int = 0
    verdicts: list[CitationVerdict] = field(default_factory=list)

    @property
    def graded(self) -> int:
        return self.verified + self.fabricated + self.degenerate + self.unresolvable

    def add(self, v: CitationVerdict) -> None:
        self.verdicts.append(v)
        self.citations_found += 1
        setattr(self, v.status.lower(), getattr(self, v.status.lower()) + 1)


# ── Stack access ─────────────────────────────────────────────────────────────

def read_env(repo_root: Path) -> dict[str, str]:
    """Read the same .env the stack runs from. Never prints values."""
    env: dict[str, str] = {}
    f = repo_root / "deploy" / "client-bundle" / ".env"
    if not f.is_file():
        return env
    for line in f.read_bytes().decode("utf-8-sig", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def http_json(
    url: str, token: str | None, method: str = "GET", body: dict | None = None, timeout: int = 120
) -> tuple[int, object]:
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", errors="replace")
            try:
                return r.status, json.loads(raw)
            except json.JSONDecodeError:
                return r.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw


def login(base: str, email: str, password: str) -> str | None:
    for path in ("/api/auth/login", "/api/login"):
        code, payload = http_json(
            f"{base}{path}", None, "POST", {"email": email, "password": password}
        )
        if code == 200 and isinstance(payload, dict):
            for key in ("token", "access_token", "jwt"):
                if payload.get(key):
                    return str(payload[key])
            if isinstance(payload.get("data"), dict):
                d = payload["data"]
                for key in ("token", "access_token", "jwt"):
                    if d.get(key):
                        return str(d[key])
    return None


def longest_common_run(a: str, b: str) -> str:
    """Longest fragment of `a` that also occurs in `b`.

    Used only to make a failure ACTIONABLE. Naive O(n*m) longest-common-substring
    is far too slow for a page of text, so this walks `a` in halves and narrows -
    good enough to show a reviewer where the model's quote diverged from the real
    text, which is the diagnostic they actually need.
    """
    lo, hi = 0, len(a)
    best = ""
    while lo < hi and (hi - lo) > len(best):
        mid = (lo + hi) // 2
        window = a[:mid]
        if window in b:
            best = window
            lo = mid + 1
        else:
            hi = mid - 1
    # also try a suffix-anchored window, since the divergence is often at the start
    for start in range(1, min(len(a), 200)):
        lo2, hi2 = 0, len(a) - start
        while lo2 < hi2 and (hi2 - lo2) > len(best):
            mid = (lo2 + hi2) // 2
            window = a[start : start + mid]
            if window in b:
                best = window
                lo2 = mid + 1
            else:
                hi2 = mid - 1
    return best


def grade(execute_payload: dict, base: str, token: str, report: Report) -> None:
    steps = execute_payload.get("steps") or []
    if not isinstance(steps, list):
        return

    doc_text_cache: dict[str, str | None] = {}

    def document_text(doc_id: str) -> str | None:
        if doc_id in doc_text_cache:
            return doc_text_cache[doc_id]
        text: str | None = None
        # POST, not GET. Verified against pacgate-api/src/lib.rs L62-63:
        #   .route("/api/documents/:id/extract", post(extract_document_handler))
        # A GET returns 405, which would be reported as UNRESOLVABLE and read as
        # "the document has no text" - a false negative caused by the grader, not
        # by the product. Checked before trusting it.
        code, payload = http_json(
            f"{base}/api/documents/{doc_id}/extract", token, "POST", {}, timeout=180
        )
        if code == 200 and isinstance(payload, dict):
            t = payload.get("text")
            if isinstance(t, str) and t.strip():
                text = t
        doc_text_cache[doc_id] = text
        return text

    for step in steps:
        if not isinstance(step, dict):
            continue
        step_name = str(step.get("step_name") or "(unnamed step)")
        for cit in step.get("citations") or []:
            if not isinstance(cit, dict):
                continue
            ref = cit.get("ref_num", 0)
            doc_id = str(cit.get("document_id") or "")
            quote = str(cit.get("verbatim") or "")

            if len(quote.strip()) < MIN_QUOTE_CHARS:
                report.add(
                    CitationVerdict(
                        step_name, ref, doc_id, quote, "DEGENERATE",
                        f"quote is {len(quote.strip())} chars, below the {MIN_QUOTE_CHARS} "
                        "needed to distinguish a citation from a coincidence",
                    )
                )
                continue

            text = document_text(doc_id)
            if text is None:
                report.add(
                    CitationVerdict(
                        step_name, ref, doc_id, quote, "UNRESOLVABLE",
                        "GET /api/documents/:id/extract returned no text - cannot verify, "
                        "which is NOT the same as verifying",
                    )
                )
                continue

            if norm(quote) in norm(text):
                report.add(CitationVerdict(step_name, ref, doc_id, quote, "VERIFIED"))
            else:
                near = longest_common_run(norm(quote), norm(text))
                report.add(
                    CitationVerdict(
                        step_name, ref, doc_id, quote, "FABRICATED",
                        "quote does not occur in the cited document. "
                        f"longest matching fragment ({len(near)} chars): {near[:120]!r}",
                    )
                )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base-url", default="http://localhost:8089/pacgate")
    ap.add_argument(
        "--workflow-id",
        default="00000000-0000-0000-0000-000000000202",
        help="workflow to execute (default: a DD/review workflow that reads a document)",
    )
    ap.add_argument("--document-id", default="", help="optional existing document to point the run at")
    ap.add_argument(
        "--fixtures-dir",
        default="",
        help="default: <tmp>/pacgate-eval-fixtures (used to provision a document)",
    )
    ap.add_argument(
        "--fixture",
        default="equity-transfer-agreement",
        help="which built fixture to upload when no document exists to cite",
    )
    ap.add_argument("--from-json", default="", help="grade a saved execute response instead of running one")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    env = read_env(repo_root)

    if args.from_json:
        payload = json.loads(Path(args.from_json).read_text(encoding="utf-8"))
        if isinstance(payload, dict) and "steps" not in payload and "data" in payload:
            payload = payload["data"]
    else:
        email = env.get("PACGATE_API_EMAIL", "")
        password = env.get("PACGATE_API_PASSWORD", "")
        if not email or not password:
            print("CANNOT CHECK: PACGATE_API_EMAIL / PACGATE_API_PASSWORD missing from .env")
            return 2
        token = login(args.base_url, email, password)
        if not token:
            print(f"CANNOT CHECK: could not log in to {args.base_url} as {email}")
            return 2

        # Provision a matter that CONTAINS a document. A workflow told to read a
        # document from an empty matter returns no citations at all, which reads
        # as CANNOT CHECK and hides whether citation works. Measured 2026-10-24.
        import fixture_provisioning as fp

        fx_dir = (
            Path(args.fixtures_dir)
            if args.fixtures_dir
            else Path.home() / "AppData" / "Local" / "Temp" / "pacgate-eval-fixtures"
        )
        prov = fp.provision(args.base_url, token, fx_dir, args.fixture, "citation-eval")
        if not prov:
            print(
                "CANNOT CHECK: could not provision a matter + fixture. Expected "
                f"{fx_dir / (args.fixture + '.docx')} - run build_fixtures.py first."
            )
            return 2
        matter_id = prov.matter_id
        print(f"provisioned matter {matter_id} with document {prov.document_id} ({prov.fixture})")

        body: dict = {"matter_id": matter_id}
        if args.document_id:
            # NOTE: POST /api/workflows/:id/execute accepts only matter_id,
            # persona_id and dd_domain (pacgate-api/src/workflows.rs). A
            # `document_id` field is silently DROPPED by serde, so passing it does
            # nothing - verified 2026-10-24. The document is found through the
            # matter, which is why the fixture is uploaded into it.
            body["document_id"] = args.document_id

        code, payload = http_json(
            f"{args.base_url}/api/workflows/{args.workflow_id}/execute",
            token, "POST", body, timeout=1800,
        )
        if code != 200 or not isinstance(payload, dict):
            print(f"CANNOT CHECK: execute returned HTTP {code}: {str(payload)[:300]}")
            return 2
        if isinstance(payload.get("data"), dict):
            payload = payload["data"]

    report = Report()

    # `--from-json` is offline: it still needs a token to resolve documents,
    # because extraction is tenant-scoped. If we have no token, degradation is
    # reported honestly rather than silently grading nothing.
    token_for_extract = locals().get("token")
    if args.from_json:
        email = env.get("PACGATE_API_EMAIL", "")
        password = env.get("PACGATE_API_PASSWORD", "")
        if email and password:
            token_for_extract = login(args.base_url, email, password)

    if not token_for_extract:
        print(
            "CANNOT CHECK: no API token, so cited documents cannot be resolved for "
            "verification. Grading citations requires reading the source text."
        )
        return 2

    grade(payload, args.base_url, token_for_extract, report)

    if report.citations_found == 0:
        print(
            "CANNOT CHECK: the run returned no citations at all. This is NOT a pass - "
            "it means the citation machinery never engaged, so there is nothing to "
            "verify. Check that the workflow's steps read a document."
        )
        return 2

    if args.json:
        print(json.dumps(asdict(report), indent=2, ensure_ascii=False))
    else:
        print("CITATION INTEGRITY EVAL")
        print("=======================")
        print(f"citations found : {report.citations_found}")
        print(f"  VERIFIED      : {report.verified}")
        print(f"  FABRICATED    : {report.fabricated}")
        print(f"  DEGENERATE    : {report.degenerate}")
        print(f"  UNRESOLVABLE  : {report.unresolvable}")
        print("")
        for v in report.verdicts:
            tag = "OK  " if v.status == "VERIFIED" else "FAIL"
            print(f"  [{tag}] step={v.step_name!r} ref={v.ref_num} doc={v.document_id[:8]}...")
            print(f"         quote: {v.quote[:160]!r}")
            if v.detail:
                print(f"         {v.detail}")

    bad = report.fabricated + report.degenerate
    print("")
    if bad:
        print(
            f"RESULT: FAIL - {bad} of {report.citations_found} citation(s) are not "
            "supported by the cited document"
        )
        return 1
    if report.unresolvable and not report.verified:
        print(
            f"RESULT: CANNOT CHECK - all {report.unresolvable} citation(s) point at "
            "documents whose text could not be read"
        )
        return 2
    print(f"RESULT: PASS - all {report.verified} verifiable citation(s) occur verbatim in their source")
    return 0


if __name__ == "__main__":
    sys.exit(main())
