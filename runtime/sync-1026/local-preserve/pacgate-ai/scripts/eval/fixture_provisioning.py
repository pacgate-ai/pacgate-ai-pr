#!/usr/bin/env python3
"""Shared provisioning for the output evals: create a matter, upload a fixture.

WHY A SHARED MODULE
===================

Both `citation_integrity.py` and `generation_reliability.py` need the same
precondition: a matter that contains exactly one document the workflow can read.
Duplicating that in each would let them drift, and a drifted precondition makes
two evals disagree about what they measured.

WHAT IT FIXED
=============

The first version of `generation_reliability.py` created an EMPTY matter and
executed the workflow against it. Result: 3 of 3 runs reported SILENT-EMPTY -
HTTP 200, zero tool calls, no document, no `max_rounds_reached` flag, no error.
That is a genuine product finding (an empty matter produces a silent empty
success), but it is NOT the thing the eval set out to measure, and reporting it
as "generation reliability" would attribute a fixture problem to the model.

So the harness now provisions the document it expects the workflow to read. The
empty-matter behaviour is worth its own assertion and is recorded in the eval
report rather than being conflated here.

WHY curl.exe FOR THE UPLOAD
===========================
Multipart with a binary file body is painful through urllib and the repo already
depends on curl.exe in `test-document-generation-e2e.ps1` (which documents that
the inline `--data-binary` form corrupts JSON through PowerShell quoting). Using
the same tool keeps one known-good path for uploads instead of two.
"""

from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import citation_integrity as ci  # noqa: E402


@dataclass
class ProvisionedMatter:
    matter_id: str
    document_id: str
    fixture: str


DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"


def create_matter(base: str, token: str, name: str) -> str | None:
    code, m = ci.http_json(
        f"{base}/api/matters", token, "POST", {"name": name, "description": "output-eval matter"}
    )
    if code not in (200, 201) or not isinstance(m, dict):
        return None
    return m.get("id")


def upload_document(base: str, token: str, matter_id: str, path: Path) -> str | None:
    r = subprocess.run(
        [
            "curl.exe", "-s", "-X", "POST", f"{base}/api/documents",
            "-H", f"Authorization: Bearer {token}",
            "-F", f"matter_id={matter_id}",
            "-F", f"file=@{path};type={DOCX_MIME}",
        ],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300,
    )
    if r.returncode != 0:
        return None
    try:
        doc = json.loads(r.stdout)
    except json.JSONDecodeError:
        return None
    return doc.get("id")


def provision(
    base: str, token: str, fixtures_dir: Path, fixture_name: str, label: str
) -> ProvisionedMatter | None:
    """Create a matter and upload one fixture into it.

    Returns None when any step fails, so the caller reports CANNOT CHECK rather
    than executing a workflow against a matter it believes has a document when it
    does not. That distinction is the whole point: without it, the eval measures
    "the model cannot read a document that is not there".
    """
    path = fixtures_dir / f"{fixture_name}.docx"
    if not path.is_file():
        return None

    matter_id = create_matter(base, token, f"{label}-{abs(hash(fixture_name)) % 100000}")
    if not matter_id:
        return None

    document_id = upload_document(base, token, matter_id, path)
    if not document_id:
        return None

    return ProvisionedMatter(matter_id, document_id, fixture_name)
