import re, sys, zlib, pathlib

# Scan the remote-access handbook PDFs for credential MARKERS.
# Prints COUNTS ONLY -- never the matched values.
H = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\assets\pacgate-ai-remote-handbook")

MARKERS = [
    "password", "passwd", "密码", "口令",
    "token", "secret", "api_key", "apikey", "API key",
    "ghp_", "github_pat_", "ssh-rsa", "PRIVATE KEY",
    "connection string", "postgresql://", "postgres://",
    "账号", "用户名", "登录", "凭据",
]

def pdf_text(p: pathlib.Path) -> str:
    """Best-effort text extraction: raw + inflated FlateDecode streams."""
    raw = p.read_bytes()
    chunks = [raw.decode("latin-1", "ignore")]
    for m in re.finditer(rb"stream\r?\n(.*?)endstream", raw, re.S):
        try:
            chunks.append(zlib.decompress(m.group(1)).decode("latin-1", "ignore"))
        except Exception:
            pass
    return "\n".join(chunks)

for p in sorted(H.joinpath("pdf").glob("*.pdf")):
    txt = pdf_text(p)
    print(f"\n=== {p.name}  ({p.stat().st_size:,} bytes) ===")
    print(f"    extracted chars: {len(txt):,}")
    hits = 0
    for mk in MARKERS:
        n = len(re.findall(re.escape(mk), txt, re.I))
        if n:
            hits += n
            print(f"    {mk!r:24} x{n}")
    print(f"    -> marker hits total: {hits}")
    # Also check for a URL/host pattern typical of remote access setup
    urls = re.findall(r"https?://[^\s\)\]\"']{4,60}", txt)
    print(f"    -> embedded URLs: {len(urls)}")
