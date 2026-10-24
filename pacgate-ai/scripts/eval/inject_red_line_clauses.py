#!/usr/bin/env python3
"""Inject the red-line clauses into the workflow prompts that lack them.

WHY A SCRIPT AND NOT 219 HAND EDITS
===================================

219 `system_prompt` blocks across 15 YAML files need the same three clauses. Hand
editing is unreviewable (a 219-hunk diff nobody reads), unrepeatable, and cannot
be re-run when a new workflow is added. This is idempotent: running it twice
changes nothing the second time, so it is safe to re-run after a sync.

WHAT IT ADDS, AND WHY THESE THREE
=================================

The clauses are the 红线 from `SOUL_Sylvie_v1.0.md` §禁止事项, which the prompts
were measured against on 2026-10-24:

    draft-for-review      4/219   1.8%
    citation/source     103/219  47.0%
    uncertainty          13/219   5.9%

A `generate_docx` prompt without them asks the model for exactly what the charter
forbids. The text below is deliberately SHORT and placed at the END of the
existing prompt, so it does not displace the practice-area instructions that are
the reason the prompt exists.

WHY THE END, NOT THE START
==========================

The step prompt is concatenated AFTER the base system prompt by
`compose_combined_prompt()` and injected under `## PRACTICE AREA INSTRUCTIONS`.
Instruction-following degrades with distance from the end of the context, and the
base prompt already carries the citation mandate - so restating it at the tail of
the step prompt is the position most likely to be honoured, and it does not
compete with the practice-area content at the top.

WHY THIS IS NOT THE WHOLE FIX
=============================

This is model-dependent: the model can still omit the label. The deterministic
fix is a paragraph injected by `pacgate-docx/src/builder.rs`, which cannot be
skipped - but that needs a Rust rebuild, and `docker.io` is unreachable on this
machine (verified 2026-10-24: `docker pull rust:1.94-bookworm` hangs, no `rust:`
image locally, no `cargo` on host). So this lands now, hot, because
`/app/workflows` is bind-mounted; the builder fix waits for the next release.

Usage
=====
    python scripts/eval/inject_red_line_clauses.py --dry-run
    python scripts/eval/inject_red_line_clauses.py --apply
    python scripts/eval/inject_red_line_clauses.py --apply --only contract_review.yaml
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, ValueError):
        pass

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prompt_contract_lint import CLAUSES, DOC_PRODUCING_TOOLS, norm  # noqa: E402

# The clause text. Kept as one block so the wording is reviewable in a single
# place, and so a change to it is one diff rather than 219.
#
# WORDING IS LOAD-BEARING - measured 2026-10-24
# ---------------------------------------------
# The first version said "须标注来源（法律法规名称与条文号、案号或文件出处）".
# That reads as "you must produce a statute name and article number", so the model
# went hunting for statutes: the `Generate review memo` step called `legal_search`
# SEVENTEEN times, hit the 10-round cap, and never reached `generate_docx`.
# Generation went from 3/3 produced to 0/3 capped - the clause caused a regression
# in the very thing it was meant to improve.
#
# The mistake was treating a DOCUMENT-REVIEW step as if it were legal research. In
# these workflows the source of truth is the document under review, not external
# law. So the clause now:
#   - names the document as the primary source (文件名与条款号)
#   - makes statute citation CONDITIONAL ("如需引用"), not mandatory
#   - states explicitly that the deliverable is the document, so the model stops
#     gathering and writes
#
# Clause 4 is the anti-wander instruction and is the part that actually fixed the
# regression. It is phrased as "完成必要的阅读后即输出" rather than "不要检索",
# because some workflows legitimately need one kb_search first.
CLAUSE_BLOCK = """
---
【输出要求（红线，必须遵守）】
1. 本文件为草稿，供律师复核后使用，不构成最终法律意见。
2. 引用所审阅文件的内容时，标注出处（文件名与条款号）；如需引用法律法规，标注名称与条文号。
3. 检索不到依据时如实说明"未检索到相关依据"，不得编造或凭模型自身知识填补。
4. 本步骤的产出是文档本身：完成必要的阅读后即调用 generate_docx 输出，不要为补充外部资料反复检索。
"""

RE_PROMPT = re.compile(r"^(\s*)system_prompt:\s*\|\s*$")
RE_TOOL = re.compile(r'^\s*tool:\s*"?([A-Za-z_][A-Za-z0-9_]*)"?\s*$')

# The separator that opens the injected block. Used to find and REPLACE a
# previously injected block, so re-running after a wording change does not stack
# two blocks on top of each other.
BLOCK_MARKER = "【输出要求（红线，必须遵守）】"


def block_satisfies(prompt_text: str) -> bool:
    """True when the prompt already carries all three clauses."""
    hay = norm(prompt_text)
    for spec in CLAUSES.values():
        if not any(norm(a) in hay for a in spec["alternatives"]):
            return False
    return True


def strip_existing_block(body: list[str]) -> list[str]:
    """Remove a previously injected clause block from a prompt body.

    Needed because the wording changed after the first sweep. Without this, a
    re-run would append a SECOND block and the prompt would carry both the old
    (regression-causing) wording and the new one - and the old one would still be
    read by the model.

    SAFETY: this only acts when the marker is actually present. A prompt author's
    own `---` separator is left untouched, because deleting everything after a
    bare separator would silently destroy legitimate prompt content - a far worse
    outcome than a duplicated block.
    """
    if not any(BLOCK_MARKER in line for line in body):
        return body

    out: list[str] = []
    for line in body:
        if BLOCK_MARKER in line:
            # Drop the separator we emitted immediately before the marker.
            while out and out[-1].strip() in ("", "---"):
                out.pop()
            break
        out.append(line)
    return out


def process_file(path: Path, apply: bool) -> tuple[int, int, int]:
    """Return (blocks_seen, blocks_patched, blocks_already_ok)."""
    raw = path.read_bytes().decode("utf-8-sig")
    lines = raw.splitlines()

    out: list[str] = []
    seen = patched = already = 0
    cur_tool = ""
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]

        mt = RE_TOOL.match(line)
        if mt:
            cur_tool = mt.group(1)

        mp = RE_PROMPT.match(line)
        if not mp:
            out.append(line)
            i += 1
            continue

        prompt_indent = len(mp.group(1))
        content_indent = prompt_indent + 2

        # Collect the block body.
        body: list[str] = []
        j = i + 1
        while j < n:
            bl = lines[j]
            if bl.strip() == "":
                body.append("")
                j += 1
                continue
            if (len(bl) - len(bl.lstrip())) <= prompt_indent:
                break
            body.append(bl)
            j += 1

        seen += 1
        text = "\n".join(b.strip() for b in body)

        # A block we injected earlier is REPLACED, not appended to. This is what
        # makes a wording change safe to re-run: the old text is removed first, so
        # the model never sees two competing instruction blocks.
        had_ours = any(BLOCK_MARKER in b for b in body)
        if had_ours:
            body = strip_existing_block(body)
            text = "\n".join(b.strip() for b in body)

        if cur_tool not in DOC_PRODUCING_TOOLS or (block_satisfies(text) and not had_ours):
            already += 1
            out.extend(lines[i:j])
            i = j
            continue

        # Emit the (possibly stripped) block, then the clause block at the same
        # indent.
        out.append(lines[i])
        out.extend(body)
        # Trim trailing blank lines inside the block so the separator is not
        # preceded by a run of empties.
        while out and out[-1].strip() == "":
            out.pop()
        pad = " " * content_indent
        for cl in CLAUSE_BLOCK.strip("\n").splitlines():
            out.append(pad + cl if cl.strip() else "")
        out.append("")
        patched += 1
        i = j

    if apply and patched:
        # Write UTF-8 WITHOUT a BOM. A BOM here would be read by the YAML loader
        # as part of the first key and break the whole file - and the repo has
        # already been bitten by encoding assumptions on this box.
        path.write_bytes(("\n".join(out) + "\n").encode("utf-8"))

    return seen, patched, already


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workflows-dir", default=None)
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    ap.add_argument("--dry-run", action="store_true", help="explicit no-op mode")
    ap.add_argument("--only", default="", help="single file name, e.g. contract_review.yaml")
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    wf_dir = (
        Path(args.workflows_dir)
        if args.workflows_dir
        else repo_root / "deploy" / "client-bundle" / "workflows"
    )
    if not wf_dir.is_dir():
        print(f"CANNOT CHECK: {wf_dir} not found")
        return 2

    files = sorted(wf_dir.glob("*.yaml"))
    if args.only:
        files = [f for f in files if f.name == args.only]
        if not files:
            print(f"CANNOT CHECK: {args.only} not found in {wf_dir}")
            return 2

    apply = args.apply and not args.dry_run
    total_seen = total_patched = total_ok = 0

    print("RED-LINE CLAUSE INJECTION" + ("" if apply else "  (DRY RUN - nothing written)"))
    print("=" * 52)
    for f in files:
        seen, patched, ok = process_file(f, apply)
        total_seen += seen
        total_patched += patched
        total_ok += ok
        if patched:
            print(f"  {f.name:<34} {patched:>3} patched, {ok:>3} already ok")

    print("")
    print(f"blocks seen    : {total_seen}")
    print(f"already ok     : {total_ok}")
    print(f"patched        : {total_patched}")
    if not apply:
        print("")
        print("DRY RUN - re-run with --apply to write.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
