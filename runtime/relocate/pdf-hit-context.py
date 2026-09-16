import re, zlib, pathlib

H = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\assets\pacgate-ai-remote-handbook")

def pdf_text(p):
    raw = p.read_bytes()
    chunks = [raw.decode("latin-1", "ignore")]
    for m in re.finditer(rb"stream\r?\n(.*?)endstream", raw, re.S):
        try:
            chunks.append(zlib.decompress(m.group(1)).decode("latin-1", "ignore"))
        except Exception:
            pass
    return "\n".join(chunks)

print("CONTEXT OF THE SINGLE 'password' HIT (value redacted)")
print("=" * 62)
for p in sorted(H.joinpath("pdf").glob("*.pdf")):
    txt = pdf_text(p)
    for m in re.finditer("password", txt, re.I):
        s, e = max(0, m.start() - 90), min(len(txt), m.end() + 90)
        frag = txt[s:e]
        # Redact anything that looks like an assigned value
        frag = re.sub(r"([:=]\s*)\S{3,}", r"\1<REDACTED>", frag)
        frag = " ".join(frag.split())
        print(f"\n[{p.name}] ...{frag}...")
