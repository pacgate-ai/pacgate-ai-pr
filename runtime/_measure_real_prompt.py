"""Decompose the REAL bound prompt (162 tools) and size the tool_search saving."""
import json

import tiktoken
from langchain_core.utils.function_calling import convert_to_openai_function

from deerflow.mcp.cache import get_cached_mcp_tools
from deerflow.tools.tools import get_available_tools

enc = tiktoken.get_encoding("cl100k_base")
T = lambda s: len(enc.encode(s))


def cost(tools):
    return T(json.dumps([convert_to_openai_function(t) for t in tools], ensure_ascii=False, default=str))


all_tools = get_available_tools()
mcp = get_cached_mcp_tools()
mcp_ids = {id(t) for t in mcp}

print("ACTUAL bound surface (no skill policy-active):")
print(f"  all bound tools            = {len(all_tools):4d}   tok={cost(all_tools):6d}")
print(f"  of which MCP               = {len(mcp):4d}   tok={cost(mcp):6d}")
print(f"  of which sandbox/builtin   = {len(all_tools)-len(mcp):4d}   tok={cost([t for t in all_tools if id(t) not in mcp_ids]):6d}")

# What tool_search deferred mode would cost: names-only listing
names = "\n".join(sorted(t.name for t in mcp))
section = f"<available-deferred-tools>\n{names}\n</available-deferred-tools>"
print("\nDEFERRED mode (tool_search.enabled=true):")
print(f"  <available-deferred-tools> names-only = {T(section):5d} tok  ({len(section)} chars)")
print(f"  + tool_search tool schema              = {cost([t for t in all_tools if t.name == 'tool_search']) or 'n/a'} tok")
print(f"  + per-discovery payload (~5 schemas)   = ~{cost(sorted(mcp, key=lambda t: t.name)[:5]):5d} tok")
print(f"\n  saving vs eager: ~{cost(mcp) - T(section):6d} tok per step")

# system prompt + dynamic reminder from the real log
print("\nREAL measured prompt (cloud, token_usage_middleware):")
for inp, cached in ((80791, 75520), (82675, 75520), (84413, 75520), (86734, 75648), (86994, 86912), (86220, 0)):
    print(f"  input={inp:6d}  cache_read={cached:6d}  uncached={inp-cached:6d}")
print("\n  composition check: tools 71678 + system 3107 + dynamic reminder ~8151 =", 71678 + 3107 + 8151)
