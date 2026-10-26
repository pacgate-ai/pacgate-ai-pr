#!/usr/bin/env python3
"""Answer-substance eval: did the output use the RIGHT facts from the document?

WHY CITATION INTEGRITY IS NOT ENOUGH
====================================

`citation_integrity.py` proves a quote really occurs in the document. That is a
necessary condition and it is NOT sufficient. A memo can cite ten genuine
sentences and still report the wrong number:

    document : "受让方应于本协议生效之日起四十五（45）个自然日内一次性支付全部价款"
    output   : "付款期限为三十（30）日 [3]"      <- real quote, wrong reading
    citation : quotes the 45-day sentence verbatim

Every existing check passes that: the quote is real, the file is OOXML, the tool
was called, the run returned 200. The memo is still wrong, and a lawyer who
relies on it reads the wrong payment term.

So this eval asks the second question: are the CONTROLLED FACTS planted in the
fixture reproduced correctly in the output?

WHY THIS IS SAFE TO AUTOMATE
============================

The fixtures are synthetic and their planted facts are exported to
`manifest.json` by `build_fixtures.py`. Each fact is a specific, unusual value
(RMB 48,000,000.00, 12.5%, 143 employees) chosen so a model cannot produce it
from prior knowledge - if it appears, it came from the document.

This is a code grader, so it is deterministic and offline. It is NOT a
correctness oracle: it cannot tell whether the legal ANALYSIS is sound. It can
only tell whether the model carried the numbers across intact, which is the
class of error that is both most common and most damaging in a first draft.

WHAT IT DOES NOT CLAIM
======================

Passing does not mean the memo is good. It means the memo did not misstate a
fact that the fixture planted. The eval report states this distinction
explicitly rather than letting a green result imply more than it earned.

Exit
====
    0  every checked fact appears in the output
    1  at least one planted fact is missing or contradicted
    2  CANNOT CHECK - no fixture/manifest, no stack, or no output to check
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import citation_integrity as ci  # noqa: E402

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, ValueError):
        pass


def load_manifest(fixtures_dir: Path, fixture_name: str) -> dict | None:
    mf = fixtures_dir / "manifest.json"
    if not mf.is_file():
        return None
    data = json.loads(mf.read_text(encoding="utf-8"))
    for entry in data.get("fixtures", []):
        if entry.get("name") == fixture_name:
            return entry
    return None


def fact_present(planted: str, hay: str) -> bool:
    """Is `planted` present in the normalised output, at a digit boundary?

    WHY THIS IS NOT A PLAIN SUBSTRING TEST
    --------------------------------------
    A bare `45` occurs inside `9145010000`, `450`, and `1450`. Measured
    2026-10-24: a plain substring test reported the payment term as PRESENT in an
    output whose only digits were an unrelated registration number. That is a
    false green, which is the failure mode this whole eval file exists to avoid -
    a wrong memo that the harness calls correct.

    So a fact that STARTS or ENDS with a digit must not be adjacent to another
    digit in the haystack. Full CJK word-boundary logic is not well-defined and is
    not attempted; this is the narrow rule that kills the observed false positive.

    Values that are purely prose (a party name, an arbitration body) keep the
    plain containment test, because a CJK boundary rule there would cause false
    REDS on legitimate re-wrapping.
    """
    needle = ci.norm(planted)
    if not needle:
        return False
    if not (needle[0].isdigit() or needle[-1].isdigit()):
        return needle in hay

    start = 0
    while True:
        i = hay.find(needle, start)
        if i < 0:
            return False
        before_ok = i == 0 or not hay[i - 1].isdigit()
        after = i + len(needle)
        after_ok = after >= len(hay) or not hay[after].isdigit()
        if before_ok and after_ok:
            return True
        start = i + 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base-url", default="http://localhost:8089/pacgate")
    ap.add_argument("--workflow-id", default="00000000-0000-0000-0000-000000000301")
    ap.add_argument("--fixture", default="equity-transfer-agreement")
    ap.add_argument("--fixtures-dir", default="")
    ap.add_argument(
        "--matter-id",
        default="",
        help="grade an existing matter's documents instead of provisioning a new one",
    )
    ap.add_argument("--from-json", default="", help="grade a saved execute response")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    fx_dir = (
        Path(args.fixtures_dir)
        if args.fixtures_dir
        else Path.home() / "AppData" / "Local" / "Temp" / "pacgate-eval-fixtures"
    )

    fixture = load_manifest(fx_dir, args.fixture)
    if not fixture:
        print(
            f"CANNOT CHECK: no manifest entry for '{args.fixture}' in {fx_dir / 'manifest.json'}. "
            "Run build_fixtures.py --out <dir> first."
        )
        return 2
    planted: dict[str, str] = fixture.get("planted_facts") or {}
    if not planted:
        print("CANNOT CHECK: the fixture declares no planted facts, so substance cannot be graded")
        return 2

    # Set on BOTH branches so the document lookup below always has a matter to
    # query. `token` is only bound on the live branch, which is why the document
    # read is guarded on it.
    matter_for_docs = args.matter_id or ""
    token = None

    if args.from_json:
        payload = json.loads(Path(args.from_json).read_text(encoding="utf-8"))
        if isinstance(payload, dict) and "steps" not in payload and "data" in payload:
            payload = payload["data"]
    else:
        env = ci.read_env(repo_root)
        email, password = env.get("PACGATE_API_EMAIL", ""), env.get("PACGATE_API_PASSWORD", "")
        if not email or not password:
            print("CANNOT CHECK: PACGATE_API_EMAIL / PACGATE_API_PASSWORD missing from .env")
            return 2
        token = ci.login(args.base_url, email, password)
        if not token:
            print("CANNOT CHECK: login failed")
            return 2

        import fixture_provisioning as fp

        prov = fp.provision(args.base_url, token, fx_dir, args.fixture, "substance-eval")
        if not prov:
            print(f"CANNOT CHECK: could not provision {args.fixture}.docx from {fx_dir}")
            return 2
        matter_for_docs = prov.matter_id
        print(f"provisioned matter {prov.matter_id} with document {prov.document_id}")

        code, payload = ci.http_json(
            f"{args.base_url}/api/workflows/{args.workflow_id}/execute",
            token, "POST", {"matter_id": prov.matter_id}, timeout=1800,
        )
        if code != 200 or not isinstance(payload, dict):
            print(f"CANNOT CHECK: execute returned HTTP {code}")
            return 2
        if isinstance(payload.get("data"), dict):
            payload = payload["data"]

    # ── What to grade: the DOCUMENT, not the narration ───────────────────────
    #
    # MEASURED 2026-10-24: grading the step narration made this eval FLAKY - 2 of
    # 3 runs reported `RMB 48,000,000.00` missing while the generated memo
    # contained it. The cause is not the model: the deliverable is the .docx, and
    # the narration is a short summary of it. A summary legitimately omits detail
    # that the document carries.
    #
    # A gate that fails on correct behaviour is worse than no gate, because the
    # reflex is to re-run it until it passes - the same lesson
    # test-document-generation-e2e.ps1 records about scraping ids out of prose.
    #
    # So the primary source is the generated document's text, read from disk. The
    # narration is kept as a FALLBACK only, for the case where no document was
    # produced (which generation_reliability.py reports separately).
    parts: list[str] = []
    doc_texts: list[str] = []
    doc_ids: list[str] = []

    for step in payload.get("steps") or []:
        if not isinstance(step, dict):
            continue
        if step.get("content"):
            parts.append(str(step["content"]))
    if payload.get("final_content"):
        parts.append(str(payload["final_content"]))

    # Find the documents this run created, via the DB (authoritative), then read
    # each one's text through the same extract endpoint the product uses.
    #
    # `matter_for_docs` is set explicitly on both branches rather than probed with
    # locals(): the first version used `locals().get("prov")`, which silently
    # returned None on the --from-json path and made the eval grade narration
    # instead of the document without saying so.
    if matter_for_docs and token:
        try:
            import subprocess

            r = subprocess.run(
                ["docker", "exec", "pacgate-db", "psql", "-U", "pacgate", "-d", "pacgate",
                 "-t", "-A", "-c",
                 f"SELECT id FROM documents WHERE matter_id='{matter_for_docs}' "
                 "AND format='docx' ORDER BY created_at DESC LIMIT 3"],
                capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60,
            )
            for line in (r.stdout or "").splitlines():
                did = line.strip()
                if not did:
                    continue
                code, ex = ci.http_json(
                    f"{args.base_url}/api/documents/{did}/extract", token, "POST", {}, timeout=180
                )
                if code == 200 and isinstance(ex, dict) and (ex.get("text") or "").strip():
                    doc_texts.append(ex["text"])
                    doc_ids.append(did)
        except Exception:
            pass

    produced = "\n".join(parts)
    document = "\n".join(doc_texts)

    if not produced.strip() and not document.strip():
        print(
            "CANNOT CHECK: the run produced no text and no document, so there is nothing "
            "to grade. This is a generation failure, not a substance failure - see "
            "generation_reliability.py."
        )
        return 2

    # Grade the document when there is one; fall back to narration otherwise.
    graded_source = "generated document" if document.strip() else "step narration"
    hay = ci.norm(document if document.strip() else produced)

    missing: list[tuple[str, str]] = []
    present: list[tuple[str, str]] = []
    for key, value in planted.items():
        if fact_present(value, hay):
            present.append((key, value))
        else:
            missing.append((key, value))

    if args.json:
        print(json.dumps(
            {"fixture": args.fixture, "planted": len(planted), "graded_source": graded_source,
             "documents_read": len(doc_ids),
             "present": [{"fact": k, "value": v} for k, v in present],
             "missing": [{"fact": k, "value": v} for k, v in missing]},
            indent=2, ensure_ascii=False,
        ))
    else:
        print("ANSWER SUBSTANCE EVAL")
        print("=====================")
        print(f"fixture : {args.fixture}")
        print(f"planted : {len(planted)} fact(s)")
        print(f"graded  : {graded_source}" + (f" ({len(doc_ids)} docx read)" if doc_ids else ""))
        print("")
        for k, v in present:
            print(f"  [OK  ] {k:<32} {v}")
        for k, v in missing:
            print(f"  [MISS] {k:<32} {v}  <- not carried into the output")

    print("")
    if missing:
        print(
            f"RESULT: FAIL - {len(missing)} of {len(planted)} planted fact(s) did not appear "
            "in the output. A memo that omits or contradicts a planted value cannot be "
            "relied on, however good its citations are."
        )
        return 1
    print(
        f"RESULT: PASS - all {len(planted)} planted fact(s) carried into the output. "
        "This proves the FACTS survived, NOT that the legal analysis is sound."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
