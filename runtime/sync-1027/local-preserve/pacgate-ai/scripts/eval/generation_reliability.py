#!/usr/bin/env python3
"""Generation reliability probe: does the document-producing step produce?

WHY THIS IS SEPARATE FROM THE CITATION EVAL
===========================================

`test-document-generation-e2e.ps1` asserts that ONE execution reaches
`generate_docx` and lands a file. That is a single sample, and this repo already
documented why a single sample is not enough:

  "The 0.1.28 defect answered POST /api/workflows/:id/execute with HTTP 500 on
   1 run in 3, while the document was written anyway. Every gate runs a route
   ONCE, so a 1-in-3 defect had a ~67% chance of passing."

The same reasoning applies in the opposite direction: a step that produces a
document on 2 runs of 3 ALSO passes a single-shot gate, and that is the state
measured here on 2026-10-24 - the `generate_docx` step hit its tool-round cap
and returned empty content while the route answered HTTP 200.

So this measures the RATE, not a single outcome, and it counts the two states
that a single-shot gate conflates:

  produced      - `generate_docx` in tools_used AND a new document row appeared
  capped        - max_rounds_reached=True (tools ran, no document, no error)
  silent-empty  - neither: HTTP 200 with no document and no cap flag

The last one is the dangerous state. It is indistinguishable from success unless
you look at the documents table.

Usage
=====
    python scripts/eval/generation_reliability.py --matter-id <uuid> --runs 3
    python scripts/eval/generation_reliability.py --workflow-id <uuid> --runs 5 --json

Exit
====
    0  every run produced a document
    1  at least one run did not (rate reported)
    2  CANNOT CHECK - stack down / no credentials / cannot count documents
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import citation_integrity as ci  # noqa: E402

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, ValueError):
        pass


def count_documents(matter_id: str) -> int | None:
    """Count document rows for a matter, straight from the DB.

    The documents TABLE is authoritative, not the model's prose and not the HTTP
    status - `test-document-generation-e2e.ps1` learned this the hard way and its
    comment says so. A row count is also the only signal that distinguishes
    "generated and reported" from "generated but the summary was truncated".
    """
    try:
        r = subprocess.run(
            ["docker", "exec", "pacgate-db", "psql", "-U", "pacgate", "-d", "pacgate",
             "-t", "-A", "-c",
             f"SELECT count(*) FROM documents WHERE matter_id='{matter_id}'"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60,
        )
        if r.returncode != 0:
            return None
        return int((r.stdout or "0").strip() or 0)
    except (subprocess.SubprocessError, ValueError):
        return None


@dataclass
class RunOutcome:
    run: int
    http: int
    tools: int
    called_generate: bool
    max_rounds_reached: bool
    docs_before: int | None
    docs_after: int | None
    state: str


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base-url", default="http://localhost:8089/pacgate")
    ap.add_argument("--workflow-id", default="00000000-0000-0000-0000-000000000301")
    ap.add_argument("--matter-id", default="", help="matter holding the fixture document")
    ap.add_argument(
        "--fixtures-dir",
        default="",
        help="default: <tmp>/pacgate-eval-fixtures. Used to provision a matter + document.",
    )
    ap.add_argument(
        "--fixture",
        default="equity-transfer-agreement",
        help="which built fixture to upload when --matter-id is not given",
    )
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    env = ci.read_env(repo_root)
    email, password = env.get("PACGATE_API_EMAIL", ""), env.get("PACGATE_API_PASSWORD", "")
    if not email or not password:
        print("CANNOT CHECK: PACGATE_API_EMAIL / PACGATE_API_PASSWORD missing from .env")
        return 2

    token = ci.login(args.base_url, email, password)
    if not token:
        print("CANNOT CHECK: login failed")
        return 2

    matter_id = args.matter_id
    if not matter_id:
        # Provision a matter WITH a document. Measuring against an empty matter
        # reports SILENT-EMPTY on 3 of 3 runs (observed 2026-10-24) and blames the
        # model for a missing fixture - see fixture_provisioning.py.
        import fixture_provisioning as fp

        fx_dir = (
            Path(args.fixtures_dir)
            if args.fixtures_dir
            else Path.home() / "AppData" / "Local" / "Temp" / "pacgate-eval-fixtures"
        )
        prov = fp.provision(args.base_url, token, fx_dir, args.fixture, "gen-reliability")
        if not prov:
            print(
                f"CANNOT CHECK: could not provision a matter + fixture. Expected "
                f"{fx_dir / (args.fixture + '.docx')} - run build_fixtures.py first."
            )
            return 2
        matter_id = prov.matter_id
        print(f"provisioned matter {matter_id} with document {prov.document_id} ({prov.fixture})")

    before = count_documents(matter_id)
    if before is None:
        print("CANNOT CHECK: could not read the documents table")
        return 2

    outcomes: list[RunOutcome] = []
    for i in range(1, args.runs + 1):
        code, p = ci.http_json(
            f"{args.base_url}/api/workflows/{args.workflow_id}/execute",
            token, "POST", {"matter_id": matter_id}, timeout=1800,
        )
        steps = (p.get("steps") if isinstance(p, dict) else None) or []
        gen_steps = [s for s in steps if "generate" in str(s.get("tool") or "")]
        g = gen_steps[0] if gen_steps else {}
        tools = g.get("tools_used") or []
        called = any(t in ("generate_docx", "create_document", "generate_document") for t in tools)
        capped = bool(g.get("max_rounds_reached"))

        after = count_documents(matter_id)
        produced = bool(after is not None and before is not None and after > before)

        if produced:
            state = "produced"
        elif capped:
            state = "capped"
        else:
            state = "silent-empty"

        outcomes.append(RunOutcome(i, code, len(tools), called, capped, before, after, state))
        before = after if after is not None else before

    if args.json:
        print(json.dumps([asdict(o) for o in outcomes], indent=2, ensure_ascii=False))
    else:
        print("GENERATION RELIABILITY")
        print("======================")
        print(f"workflow : {args.workflow_id}")
        print(f"matter   : {matter_id}")
        print("")
        for o in outcomes:
            print(f"  run {o.run}: http={o.http} tools={o.tools:<3} "
                  f"called_generate={o.called_generate!s:<5} cap={o.max_rounds_reached!s:<5} "
                  f"docs {o.docs_before}->{o.docs_after}  => {o.state.upper()}")

    produced = sum(1 for o in outcomes if o.state == "produced")
    capped = sum(1 for o in outcomes if o.state == "capped")
    silent = sum(1 for o in outcomes if o.state == "silent-empty")
    print("")
    print(f"produced     : {produced}/{len(outcomes)}")
    print(f"capped       : {capped}/{len(outcomes)}")
    print(f"silent-empty : {silent}/{len(outcomes)}")

    if produced == len(outcomes):
        print("RESULT: PASS - every run produced a document")
        return 0
    print(
        f"RESULT: FAIL - {len(outcomes) - produced} of {len(outcomes)} run(s) produced no "
        "document while the route still answered HTTP 200"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
