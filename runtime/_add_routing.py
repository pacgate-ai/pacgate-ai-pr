"""Add MCP routing hints to the live connector config and the template.

Without `routing.mode = "prefer"` + non-empty keywords, build_mcp_routing_middleware
returns None and enabling tool_search reproduces the 2026-09-12 "deferred, not promoted"
loop. These keywords are the load-bearing half of the fix.

Priority ordering reflects the due-diligence path: statute/citation verification first,
then case and company lookup, then general research and memory.
"""
import json
import pathlib
import shutil

BUNDLE = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle")
LIVE = BUNDLE / "deer-flow-extensions-config.json"
TEMPLATE = BUNDLE / "deer-flow-extensions-config.template.json"

# server -> (priority, [keywords])  Keywords are matched case-insensitively as
# substrings against the latest real user message.
ROUTING = {
    "pkulaw-citation-validator": (95, ["引用", "引文", "citation", "核验", "validate", "法条校验"]),
    "pkulaw-law-search": (90, ["法条", "法规", "法条检索", "statute", "legal provision", "法律法规", "司法解释"]),
    "pkulaw-law-keyword": (85, ["法规关键词", "关键词检索", "keyword search"]),
    "pkulaw-case-semantic-search": (85, ["案例", "判例", "case", "precedent", "裁判文书"]),
    "pkulaw-case-keyword": (82, ["案例关键词"]),
    "yuandian-law": (85, ["法规", "法条", "司法解释", "legal research"]),
    "yuandian-case": (85, ["案例", "判例", "case", "precedent"]),
    "yuandian-company": (80, ["公司", "企业", "工商", "company", "entity", "关联企业"]),
    "yuandian-securities": (75, ["证券", "securities", "监管文件", "上市公司"]),
    "vaquill": (70, ["美国法", "美国法律", "US legal", "Delaware", "境外法律"]),
    "openviking": (60, ["记忆", "recall", "remember", "之前", "历史会话"]),
    "pacgate": (60, ["知识库", "RAG", "检索", "knowledge base"]),
    "firecrawl": (55, ["网页", "抓取", "爬取", "web", "scrape", "官网"]),
    "officecli": (55, ["文档", "docx", "excel", "pptx", "表格", "生成报告"]),
}


def apply(path: pathlib.Path, label: str) -> int:
    if not path.exists():
        print(f"[skip] {label}: absent")
        return 0
    shutil.copy2(path, path.with_suffix(path.suffix + ".bak.prerouting"))
    data = json.loads(path.read_text(encoding="utf-8"))
    servers = data.get("mcpServers", {})
    added = 0
    for name, (priority, keywords) in ROUTING.items():
        if name not in servers:
            continue
        servers[name]["routing"] = {"mode": "prefer", "priority": priority, "keywords": keywords}
        added += 1
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[ok]   {label}: {added} server(s) got routing hints (of {len(servers)} present)")
    return added


total = apply(LIVE, "live deer-flow-extensions-config.json")
total += apply(TEMPLATE, "template")

# verify round-trip preserves CJK and adds what we expect
data = json.loads(LIVE.read_text(encoding="utf-8"))
prefer = [n for n, s in data["mcpServers"].items() if s.get("routing", {}).get("mode") == "prefer"]
cjk = sum(1 for s in data["mcpServers"].values() for k in s.get("routing", {}).get("keywords", []) if any("\u4e00" <= c <= "\u9fff" for c in k))
print(f"\nverify: {len(prefer)} server(s) at mode=prefer, {cjk} CJK keywords present")
print("verify: sample ->", json.dumps(data["mcpServers"]["pkulaw-law-search"]["routing"], ensure_ascii=False))
print("verify: total servers still", len(data["mcpServers"]))
