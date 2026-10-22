"""Build patches/deer-flow-mcp-tools.py: live v2.0.0 loader + MCP routing tags.

The live loader knows the source server per tool but only tags `deerflow_mcp` (in
tools/tools.py, after the server grouping is lost). Routing needs the server-scoped
metadata, so this inserts the tagging at the one place that has `servers_config` and
`ExtensionsConfig` in scope.
"""
import ast
import pathlib

LIVE = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\runtime\_port\live_mcp_tools.py")
OUT = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\patches\deer-flow-mcp-tools.py")

src = LIVE.read_text(encoding="utf-8")

# ── 1. imports ──
old_imp = "from deerflow.config.extensions_config import ExtensionsConfig\n"
new_imp = "from deerflow.config.extensions_config import ExtensionsConfig, resolve_effective_mcp_routing\n"
assert old_imp in src, "ExtensionsConfig import anchor not found"
src = src.replace(old_imp, new_imp, 1)

old_sync = "from deerflow.tools.sync import make_sync_tool_wrapper\n"
new_sync = "from deerflow.tools.mcp_metadata import tag_mcp_routing\nfrom deerflow.tools.sync import make_sync_tool_wrapper\n"
assert old_sync in src, "sync import anchor not found"
src = src.replace(old_sync, new_sync, 1)

# ── 2. docstring note ──
old_doc = '"""Load MCP tools using langchain-mcp-adapters with stdio session pooling."""\n'
new_doc = '''"""Load MCP tools using langchain-mcp-adapters with stdio session pooling.

PacGate patch (2026-10-17): tags each loaded MCP tool with its routing metadata
(``deerflow_mcp_routing``) while the source server and its ``ExtensionsConfig`` entry are
still in scope. The v2.0.0 base tags only ``deerflow_mcp``, and does it in ``tools/tools.py``
after the per-server grouping has already been flattened -- too late to attach
server-scoped routing hints. Without this, ``tool_search`` has nothing to auto-promote from
and falls back to the 2026-09-12 "deferred, not promoted" loop.
"""
'''
assert old_doc in src, "docstring anchor not found"
src = src.replace(old_doc, new_doc, 1)

# ── 3. tag inside the per-tool loop ──
old_loop = '''            if tool_server is not None:
                transport = servers_config[tool_server].get("transport", "stdio")
                if transport == "stdio":'''
new_loop = '''            if tool_server is not None:
                transport = servers_config[tool_server].get("transport", "stdio")

                # Routing metadata must be attached while we still know which server
                # produced this tool. Keyed on the RAW (unprefixed) tool name, because
                # the prefix is a presentation concern added by the adapter and the
                # operator-authored config binds to the server's own tool name.
                server_cfg = extensions_config.mcp_servers.get(tool_server)
                raw_name = tool.name
                prefix = f"{tool_server}_"
                if raw_name.startswith(prefix):
                    raw_name = raw_name[len(prefix):]
                try:
                    routing = resolve_effective_mcp_routing(server_cfg, raw_name)
                except Exception:
                    logger.warning("MCP routing metadata for server '%s' tool '%s' could not be resolved; leaving routing to the model (tool_search).", tool_server, raw_name, exc_info=True)
                else:
                    if routing.get("mode") == "prefer" and routing.get("keywords"):
                        tag_mcp_routing(tool, routing)

                if transport == "stdio":'''
assert old_loop in src, "per-tool loop anchor not found"
src = src.replace(old_loop, new_loop, 1)

OUT.write_text(src, encoding="utf-8", newline="\n")
ast.parse(src)

print("written:", OUT.name, OUT.stat().st_size, "bytes")
print("imports  :", src.count("resolve_effective_mcp_routing"), src.count("tag_mcp_routing"))
print("tag site :", "tag_mcp_routing(tool, routing)" in src)
print("live body:", all(k in src for k in ("async def get_mcp_tools", "def _make_session_pool_tool", "def _convert_call_tool_result")))
print("no deerflow.constants:", "deerflow.constants" not in src)
