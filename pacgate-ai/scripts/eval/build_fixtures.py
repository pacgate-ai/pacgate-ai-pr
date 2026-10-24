#!/usr/bin/env python3
"""Deterministic fixture corpus for the PacGate output evals.

WHY SYNTHETIC, AND WHY GENERATED
================================

The repo has ZERO test fixtures. `test-legal-journey.ps1` builds its PDF inside
the OCR container at runtime for exactly this reason, and this follows that
precedent.

Two constraints forced the choice:

  1. The only real legal documents in the tree are 百宸 CLIENT material already
     tracked in a public repo (a 37.7 MB due-diligence scan among them). An eval
     that reads them would make client documents the test corpus on every run,
     widening an exposure that is already an open incident - see AGENTS.md
     "Credentials safety".
  2. A committed binary fixture rots: nobody can review a .docx in a diff, so a
     fixture that drifts is undetectable. Text built from a literal here IS
     reviewable.

So every fixture is built from text defined in THIS file. If a fixture needs to
change, the diff shows the changed words.

WHAT MAKES THESE USEFUL FOR GRADING CITATIONS
=============================================

Each fixture carries facts that are:

  - SPECIFIC and UNUSUAL (an amount, a date, a party name) so a model cannot
    reproduce them from prior knowledge - a citation quoting them must have come
    from the document;
  - CONTROLLED - the planted facts are exported in the manifest, so a later
    check can ask "did the output cite the right amount?" rather than only "is
    the quote non-empty";
  - CJK-native with full-width punctuation, because that is where the extraction
    and byte-slicing defects actually lived (the 0.1.26 panic, the CJK
    octal-path skip).

Usage
=====
    python scripts/eval/build_fixtures.py --out <dir>
    python scripts/eval/build_fixtures.py --out <dir> --json
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from dataclasses import dataclass, asdict
from pathlib import Path
from xml.sax.saxutils import escape

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, ValueError):
        pass


@dataclass
class Fixture:
    name: str
    paragraphs: list[str]
    # Facts a correct output must be able to cite. Exported so the eval can check
    # substance, not just quote-existence.
    planted_facts: dict[str, str]


FIXTURES: list[Fixture] = [
    Fixture(
        name="equity-transfer-agreement",
        paragraphs=[
            "股权转让协议",
            "本协议由以下双方于二〇二五年六月十八日在上海市浦东新区签署：",
            "转让方：杭州晨曦投资合伙企业（有限合伙），统一社会信用代码 91330100MA2XXXXXXX。",
            "受让方：宁波远望创业投资有限公司，统一社会信用代码 91330200MA8YYYYYYY。",
            "第一条 标的股权",
            "转让方同意将其持有的目标公司上海云枢数据科技有限公司百分之十二点五（12.5%）的股权转让予受让方。",
            "第二条 转让价款",
            "本次股权转让的总价款为人民币肆仟捌佰万元整（RMB 48,000,000.00）。",
            "受让方应于本协议生效之日起四十五（45）个自然日内一次性支付全部价款。",
            "第三条 陈述与保证",
            "转让方保证其对标的股权拥有完整、无瑕疵的所有权，标的股权不存在任何质押、查封或其他权利负担。",
            "第四条 违约责任",
            "任何一方违反本协议约定的，应向守约方支付总价款百分之二十（20%）的违约金。",
            "第五条 争议解决",
            "因本协议引起的或与本协议有关的任何争议，双方应友好协商解决；协商不成的，任何一方均可向上海国际经济贸易仲裁委员会提起仲裁。",
            "第六条 生效条件",
            "本协议自双方签字盖章之日起生效。",
        ],
        planted_facts={
            "transferred_percentage": "12.5%",
            "total_consideration": "RMB 48,000,000.00",
            "payment_days": "45",
            "penalty_rate": "20%",
            "arbitration_body": "上海国际经济贸易仲裁委员会",
            "counterparty": "宁波远望创业投资有限公司",
        },
    ),
    Fixture(
        name="due-diligence-checklist",
        paragraphs=[
            "法律尽职调查清单",
            "一、主体资格",
            "核查目标公司营业执照、公司章程、股东名册是否齐备，是否存在出资不实或抽逃出资的情形。",
            "二、股权结构",
            "核查是否存在股权代持、一致行动安排或表决权委托，应取得相关书面协议。",
            "三、重大合同",
            "核查标的金额超过人民币伍佰万元（RMB 5,000,000.00）的合同，并关注控制权变更条款。",
            "四、知识产权",
            "核查目标公司名下登记商标共二十七（27）件，其中三（3）件存在异议程序未决。",
            "五、劳动人事",
            "核查是否存在未决劳动争议，目标公司现有在职员工一百四十三（143）人。",
            "六、诉讼仲裁",
            "核查目标公司作为被告的未决诉讼共二（2）件，标的金额合计人民币叁佰壹拾万元（RMB 3,100,000.00）。",
        ],
        planted_facts={
            "material_contract_threshold": "RMB 5,000,000.00",
            "trademark_count": "27",
            "trademark_disputed": "3",
            "employee_count": "143",
            "litigation_count": "2",
            "litigation_amount": "RMB 3,100,000.00",
        },
    ),
]

# Minimal OOXML. A real .docx is a zip with word/document.xml; this produces one
# that Word, python-docx and the platform's own docx reader all accept. Building
# it by hand avoids adding python-docx as a dependency to a repo that has none.
_CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>"""

_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""


def _document_xml(paragraphs: list[str]) -> str:
    body = []
    for i, p in enumerate(paragraphs):
        # First paragraph is the title: make it a Heading1 so the fixture also
        # exercises heading extraction.
        style = '<w:pPr><w:pStyle w:val="Heading1"/></w:pPr>' if i == 0 else ""
        body.append(f'<w:p>{style}<w:r><w:t xml:space="preserve">{escape(p)}</w:t></w:r></w:p>')
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        f'<w:body>{"".join(body)}</w:body></w:document>'
    )


def write_docx(path: Path, paragraphs: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", _CONTENT_TYPES)
        z.writestr("_rels/.rels", _RELS)
        z.writestr("word/document.xml", _document_xml(paragraphs))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="directory to write fixtures + manifest into")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    manifest = []
    for fx in FIXTURES:
        p = out / f"{fx.name}.docx"
        write_docx(p, fx.paragraphs)
        entry = asdict(fx)
        entry["path"] = str(p)
        entry["bytes"] = p.stat().st_size
        manifest.append(entry)

    mf = out / "manifest.json"
    mf.write_text(
        json.dumps(
            {
                "why": (
                    "Fixtures are built, not committed. Text lives in "
                    "scripts/eval/build_fixtures.py so a change is reviewable in a diff."
                ),
                "fixtures": manifest,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    if args.json:
        print(json.dumps(manifest, indent=2, ensure_ascii=False))
    else:
        print(f"built {len(manifest)} fixture(s) into {out}")
        for e in manifest:
            print(f"  {Path(e['path']).name}  {e['bytes']} bytes  "
                  f"{len(e['planted_facts'])} planted fact(s)")
        print(f"manifest: {mf}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
