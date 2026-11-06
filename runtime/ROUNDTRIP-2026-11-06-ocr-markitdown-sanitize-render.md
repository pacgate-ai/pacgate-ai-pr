# Document round-trip: OCR → markitdown → sanitize → re-render → re-extract

Date: 2026-11-06 · Gate: `pacgate-ai/scripts/test-document-roundtrip-e2e.ps1`

## What was asked

Test document OCR, markitdown, PDF extraction, sanitization, and docx/pdf
re-render and generation **as a round trip**, end to end.

## Result

**30 passed, 0 failed, 0 skipped.**

| # | Case | Assertions |
|---|---|---|
| 1 | OCR (raster PDF, no text layer) | 126 chars, `incomplete=false`, digit run read |
| 2 | PDF extraction (text layer, native) | identifier extracted, keep-token present, no OCR fallback |
| 3 | Sanitization | `verdict=pass`, ID and phone gone, `CN_*` token minted, keep-token survives |
| 4 | markitdown via `pacgate_convert_document` | reported, see "Defect" below |
| 4b | markitdown on the binary directly | 199 chars, body preserved, identifier seen |
| 5 | Re-render sanitized text | `.docx` 36,761 B, `.pdf` 1,522 B |
| 6 | Re-extract the regenerated files | real OOXML, **officecli validate clean**, no identifier in either, keep-token in both, pdf text layer readable |
| 7 | Identifier **only** in header/footer | extraction **read** it — the prefix scan works |

The round trip closes: sanitized text → new docx and new pdf → re-extracted →
**no identifier returns, the keep-token does, and both artifacts are valid**.

## 🔴 Defect: markitdown cannot convert a sanitized document

`pacgate_convert_document` raises:

```
UnsupportedFormatException: Could not convert stream to Markdown.
No converter attempted a conversion, suggesting that the filetype is
simply not supported.
```

**Cause, measured.** After sanitize, `GET /api/documents/:id/download` serves:

```
HTTP/1.1 200 OK
Content-Type: text/markdown; charset=utf-8
content-disposition: attachment; filename="ct2.md"
```

…for a **PDF** upload. `server.py:726-733` picks the temp-file suffix from the
response `content-type`:

```python
if "pdf" in content_type:  suffix = ".pdf"
elif "wordprocessing" in content_type or "docx" in content_type: suffix = ".docx"
...
# text/markdown matches NOTHING -> suffix = "" -> markitdown has no converter
```

So after sanitization there are no document bytes left for a binary converter to
read, and `pacgate_convert_document` can never succeed on a sanitized binary.
`pypdf` is also absent from the MCP image (only `pdfminer` is installed), so the
pdf path has a second, latent gap.

**Not a regression** — this is the product shape the format gate already flags as
`WARN` ("download serves the original… or a sanitized rendering"), documented in
`deploy/DEFECT-sanitized-content-not-served.md`. What is new here is the precise
consequence: *convert-after-sanitize does not work at all*, rather than returning
the original's markdown.

**Options (product decision, not made here):**

1. Have `download` serve the original binary for convert and a separate
   `?rendition=sanitized` for the sanitized text — restores convert, keeps egress
   explicit.
2. Give `pacgate_convert_document` a `version`/`rendition` parameter so it can ask
   for `original`, and derive the suffix from the document's recorded `format`
   rather than from an HTTP header.
3. Accept it: convert is only meaningful pre-sanitize, and the agent should read
   `sanitized_text` instead. Then the tool's own docstring ("Convert a stored
   document to Markdown") is misleading and should say so.

Option 2 is the smallest change that makes the agent path work; option 1 is the
cleanest contract.

## Positive finding: the header/footer fail-open hole is closed

`text_extract.rs` documents that every shipped converter except the product's own
prefix scan missed headers and footers, so an identifier living only there would
egress unredacted. Case 7 confirms the deployed extractor **does** read both.
markitdown does not (it reads `word/document.xml` only) — which is why the gate
uses the product's extraction for the sanitize path and markitdown only for
conversion.

## Coverage added

`run-all-checks.ps1` now runs this gate in the live-stack section, next to
`test-format-coverage-e2e.ps1`, which it extends: that gate proves
upload → extract → sanitize → convert; this one proves the **re-render and
re-extract** half it never covered.

## Fixtures

Built by the gate on every run, so they cannot rot:

- `.docx` with the identifier in body **and** header **and** footer
- `.docx` with the identifier **only** in header/footer
- raster PDF (no text layer → OCR required)
- text-layer PDF (native extraction)

A `SETTLEMENT-CLAUSE-KEEP` token rides alongside every fixture so a passing run
cannot be one that silently blanked the document.
