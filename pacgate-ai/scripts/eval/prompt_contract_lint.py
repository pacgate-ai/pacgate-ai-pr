#!/usr/bin/env python3
"""Static prompt-contract linter for the PacGate workflow library.

WHY THIS EXISTS
===============

`run-all-checks.ps1` had 48 gates and every one of them was PLUMBING: does the
file exist, is it OOXML, is the mount right, did the tool name appear in
`tools_used`. Searched all 113 scripts for `citation|引用|草稿|fabricat|hallucin`
and for `CITATIONS` - the only hits were two unrelated identity-fabrication
warnings in `test-sync-capability.ps1`. Nothing asserted that a PROMPT says what
the product promises, and nothing asserted that a GENERATED document obeys it.

The base system prompt (`crates/pacgate-agent/src/system_prompt_base.txt`)
mandates three red-line behaviours:

  1. citations with a `<CITATIONS>` block and verbatim quotes <= 25 words
  2. docx structure (H1->H2->H3 with no skipped levels, signature page)
  3. `read_document` after `generate_docx`

A step prompt is injected UNDER the heading `## PRACTICE AREA INSTRUCTIONS`
alongside the base prompt, concatenated with a bare '\\n\\n' by
`compose_combined_prompt()`. There is no precedence marker and no conflict
resolution, so a step prompt that says nothing about citations does not inherit
them - it competes with them at equal weight.

WHAT THIS LINT ASSERTS (deterministic, no LLM, no egress)
=========================================================

For every workflow whose final step emits a document, its `system_prompt` must
carry the clauses that make the output reviewable by a lawyer:

  RED_LINE_DRAFT      - the output is a draft for review, not a final opinion
  RED_LINE_CITATION   - every legal conclusion names its source
  RED_LINE_UNCERTAIN  - an unfound source is reported, never silently filled

These three are not style preferences. They are the 红线 from
`SOUL_Sylvie_v1.0.md` section 禁止事项:

  "不出具\"最终法律意见\"——我的一切法律产出都是供她复核的草稿"
  "检索不到依据时如实报告,不得用模型自身知识或网络内容无声填补法律结论"

A prompt that omits them asks the model to produce exactly what the charter
forbids.

THE RULE IS SCOPED, NOT BLANKET
===============================

Only DOCUMENT-PRODUCING steps are linted. A `kb_search` step or a
`read_document` step has no business declaring a draft label - requiring it
there would produce 220 false failures and the gate would stop being read. The
scope is "the step that writes a file a lawyer will sign".

Exit codes
==========
  0  every document-producing prompt carries the clauses
  1  at least one prompt is missing a clause (the lint FAILS)
  2  CANNOT CHECK - the workflow directory or the base prompt is absent

Usage
=====
    python scripts/eval/prompt_contract_lint.py
    python scripts/eval/prompt_contract_lint.py --json
    python scripts/eval/prompt_contract_lint.py --baseline <file>   # ratchet mode
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from dataclasses import dataclass, field, asdict
from pathlib import Path

# ── Console encoding ─────────────────────────────────────────────────────────
#
# On this box Python's stdout is a pipe to Windows PowerShell 5.1, whose console
# code page is GBK (cp936). Writing a Chinese workflow name to it raises
# UnicodeEncodeError, or - worse - silently emits mojibake, so a failing prompt
# is reported as `椤圭洰妗ｆ鍒濇敹` and nobody can tell WHICH prompt failed.
#
# Reconfigure to UTF-8 with a replacement handler: the report must never crash
# on a name it is reporting, and a mangled name is worse than a replaced glyph
# because it looks like real output. AGENTS.md documents this same GBK trap for
# git's CJK paths; this is the Python side of it.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, ValueError):
        pass

# ── Clause definitions ───────────────────────────────────────────────────────
#
# Each clause lists ALTERNATIVES, any one of which satisfies it. They are
# matched against the prompt with Unicode normalisation first, because a
# full-width parenthesis or an NBSP inside a Chinese prompt otherwise silently
# defeats a plain substring search - the same class of bug as the CJK octal-path
# defect in check-tracked-file-size.ps1.

CLAUSES: dict[str, dict] = {
    "RED_LINE_DRAFT": {
        "why": "the output must be labelled a draft for lawyer review, not a final opinion",
        "charter": "SOUL_Sylvie_v1.0.md 禁止事项: 不出具\"最终法律意见\"",
        "alternatives": [
            "草稿",
            "供审核",
            "供复核",
            "待复核",
            "请律师复核",
            "经律师审核",
            "初审稿",
            "draft for review",
            "for review",
            "not a final",
        ],
    },
    "RED_LINE_CITATION": {
        "why": "every legal conclusion must name a verifiable source",
        "charter": "SOUL_Sylvie_v1.0.md 价值观1 准确: 每条依据标注来源与效力状态",
        "alternatives": [
            "引用",
            "条文号",
            "法律依据",
            "标注来源",
            "效力状态",
            "来源",
            "法条",
            "案号",
            "cite",
            "citation",
            "source",
        ],
    },
    "RED_LINE_UNCERTAIN": {
        "why": "an unfound source must be reported, never silently filled from model knowledge",
        "charter": "SOUL_Sylvie_v1.0.md 禁止事项: 检索不到依据时如实报告",
        "alternatives": [
            "检索不到",
            "未检索到",
            "不得编造",
            "如实说明",
            "如实报告",
            "待确认事项",
            "拿不准",
            "无法确认",
            "不得虚构",
            "如无依据",
            "no results",
            "state that",
            "do not fabricate",
            "never fabricate",
        ],
    },
}

# Only these tools produce a document a lawyer will hand to a client.
DOC_PRODUCING_TOOLS = {"generate_docx", "create_document", "generate_document"}


def norm(s: str) -> str:
    """Normalise before matching.

    NFKC folds full-width forms to ASCII (（） -> ()), and stripping whitespace
    stops a line-wrapped clause from escaping a search. Applied to BOTH sides.
    """
    s = unicodedata.normalize("NFKC", s)
    return re.sub(r"\s+", " ", s).lower()


@dataclass
class PromptRecord:
    workflow_id: str
    name: str
    source_file: str
    tool: str
    prompt: str
    missing: list[str] = field(default_factory=list)

    @property
    def is_doc_producing(self) -> bool:
        return self.tool in DOC_PRODUCING_TOOLS


# ── A deliberately small YAML reader ─────────────────────────────────────────
#
# The library is 15 files of a very regular shape, verified before this was
# written:
#
#   - id: "<uuid>"          indent 4 (inside a list under `- id:`)
#     name: "..."
#     steps:
#       - name: "..."
#         tool: "generate_docx"     indent 6
#         parameters:
#           system_prompt: |        indent 8, block scalar, always literal
#             ...content...         indent 10+
#
# Every one of the 220 prompts uses the `|` literal block form (measured: 220/220
# are `system_prompt: |`, 0 use a quoted or folded form). Pulling in PyYAML would
# add a dependency to a repo that has none for this, and would still not tell us
# WHICH STEP a prompt belongs to - which is the whole point of the scoping rule.
# So: walk the lines, track the current workflow and current step, attach the
# block to the step that owns it.

RE_WF_ID = re.compile(r'^(\s*)-\s*id:\s*"([^"]+)"')
RE_WF_NAME = re.compile(r'^\s*name:\s*"(.*)"\s*$')
RE_TOOL = re.compile(r'^\s*tool:\s*"?([A-Za-z_][A-Za-z0-9_]*)"?\s*$')
RE_PROMPT = re.compile(r'^(\s*)system_prompt:\s*\|\s*$')


def parse_workflow_file(path: Path) -> list[PromptRecord]:
    """Return one record per step that declares a system_prompt."""
    raw = path.read_bytes().decode("utf-8-sig", errors="replace")
    lines = raw.splitlines()

    records: list[PromptRecord] = []
    wf_id = ""
    wf_name = ""
    cur_tool = ""
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]

        m = RE_WF_ID.match(line)
        if m:
            wf_id = m.group(2)
            wf_name = ""
            cur_tool = ""
            i += 1
            continue

        # A top-level `name:` belongs to the workflow only when it precedes the
        # first step; after a tool is seen it would be a step name.
        if not cur_tool:
            mn = RE_WF_NAME.match(line)
            if mn:
                wf_name = mn.group(1)
                i += 1
                continue

        mt = RE_TOOL.match(line)
        if mt:
            cur_tool = mt.group(1)
            i += 1
            continue

        mp = RE_PROMPT.match(line)
        if mp:
            prompt_indent = len(mp.group(1))
            body: list[str] = []
            i += 1
            while i < n:
                bl = lines[i]
                if bl.strip() == "":
                    body.append("")
                    i += 1
                    continue
                cur_indent = len(bl) - len(bl.lstrip())
                if cur_indent <= prompt_indent:
                    break
                body.append(bl.strip())
                i += 1
            records.append(
                PromptRecord(
                    workflow_id=wf_id,
                    name=wf_name,
                    source_file=path.name,
                    tool=cur_tool,
                    prompt="\n".join(body).strip(),
                )
            )
            continue

        i += 1

    return records


def evaluate(records: list[PromptRecord]) -> None:
    """Fill each record's `missing` list, in place."""
    for r in records:
        if not r.is_doc_producing:
            continue
        hay = norm(r.prompt)
        for clause, spec in CLAUSES.items():
            if not any(norm(a) in hay for a in spec["alternatives"]):
                r.missing.append(clause)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--workflows-dir",
        default=None,
        help="default: <repo>/deploy/client-bundle/workflows",
    )
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument(
        "--baseline",
        default=None,
        help="ratchet: allow only the prompts listed in this JSON file to fail",
    )
    ap.add_argument(
        "--write-baseline",
        default=None,
        help="record the current failures as an accepted baseline",
    )
    args = ap.parse_args()

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    wf_dir = (
        Path(args.workflows_dir)
        if args.workflows_dir
        else repo_root / "deploy" / "client-bundle" / "workflows"
    )

    if not wf_dir.is_dir():
        print(f"CANNOT CHECK: workflow directory not found: {wf_dir}", file=sys.stderr)
        return 2

    files = sorted(wf_dir.glob("*.yaml"))
    if not files:
        print(f"CANNOT CHECK: no *.yaml under {wf_dir}", file=sys.stderr)
        return 2

    records: list[PromptRecord] = []
    for f in files:
        records.extend(parse_workflow_file(f))

    if not records:
        print(
            f"CANNOT CHECK: parsed 0 system_prompt blocks from {len(files)} files "
            "- the parser no longer matches the file shape",
            file=sys.stderr,
        )
        return 2

    evaluate(records)

    doc_prompts = [r for r in records if r.is_doc_producing]
    failing = [r for r in doc_prompts if r.missing]

    # ── Ratchet support ──────────────────────────────────────────────────────
    #
    # This lint WILL fail on the current library, because 220 prompts were
    # written before the clauses were required. Failing every run makes the
    # suite permanently red, which is the documented way a gate stops being read
    # (see check-tracked-file-size.ps1's treatment of already-committed debt).
    #
    # So the honest state is a BASELINE: record today's failures, fail only on
    # REGRESSIONS, and let the count go down as prompts are fixed. The number is
    # printed on every run so the debt stays visible instead of becoming
    # background.
    accepted: set[str] = set()
    if args.baseline and Path(args.baseline).is_file():
        data = json.loads(Path(args.baseline).read_text(encoding="utf-8"))
        accepted = set(data.get("accepted_failures", []))

    if args.write_baseline:
        Path(args.write_baseline).write_text(
            json.dumps(
                {
                    "why": (
                        "Accepted prompt-contract debt. Shrink this list; never "
                        "grow it. A new entry means a new prompt shipped without a "
                        "red-line clause."
                    ),
                    "accepted_failures": sorted(r.workflow_id for r in failing),
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"wrote baseline: {args.write_baseline} ({len(failing)} entries)")

    regressions = [r for r in failing if r.workflow_id not in accepted]

    if args.json:
        print(
            json.dumps(
                {
                    "workflow_files": len(files),
                    "prompts_parsed": len(records),
                    "doc_producing": len(doc_prompts),
                    "failing": len(failing),
                    "accepted": len(accepted),
                    "regressions": len(regressions),
                    "clause_coverage": {
                        c: sum(
                            1
                            for r in doc_prompts
                            if c not in r.missing
                        )
                        for c in CLAUSES
                    },
                    "regression_detail": [asdict(r) for r in regressions],
                },
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        print("PROMPT CONTRACT LINT")
        print("====================")
        print(f"files            : {len(files)}")
        print(f"prompts parsed   : {len(records)}")
        print(f"doc-producing    : {len(doc_prompts)}")
        print("")
        print("clause coverage across document-producing prompts:")
        for c, spec in CLAUSES.items():
            have = sum(1 for r in doc_prompts if c not in r.missing)
            pct = (100.0 * have / len(doc_prompts)) if doc_prompts else 0.0
            print(f"  {c:<20} {have:>4}/{len(doc_prompts)}  ({pct:5.1f}%)")
            print(f"  {'':<20} {spec['why']}")
        print("")
        if accepted:
            print(f"accepted baseline: {len(accepted)} prompts (debt being paid down)")
        print(f"failing now      : {len(failing)}")
        print(f"REGRESSIONS      : {len(regressions)}")
        if regressions:
            print("")
            for r in regressions[:25]:
                print(
                    f"  [FAIL] {r.workflow_id}  {r.name or '(unnamed)'}  "
                    f"[{r.source_file}]  missing: {', '.join(r.missing)}"
                )
            if len(regressions) > 25:
                print(f"  ... and {len(regressions) - 25} more")

    ok = not regressions
    print("")
    print(
        "RESULT: PASS - no new prompt-contract regressions"
        if ok
        else f"RESULT: FAIL - {len(regressions)} prompt(s) missing a red-line clause"
    )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
