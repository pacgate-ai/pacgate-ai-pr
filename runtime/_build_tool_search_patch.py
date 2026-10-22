"""Build patches/deer-flow-tool-search.py: live v2.0.0 file + the routing builder.

Generated rather than hand-written so the live file's content is preserved byte-for-byte
and only the additive block is appended.
"""
import pathlib

LIVE = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\runtime\_port\live_tools_builtins_tool_search.py")
OUT = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\patches\deer-flow-tool-search.py")

src = LIVE.read_text(encoding="utf-8")

# 1. Extend the module docstring note.
src = src.replace(
    '''The agent sees deferred tool names in <available-deferred-tools> but cannot
call them until it fetches their full schema via the tool_search tool. The
deferred set rides on a build-time closure and promotion lives in per-thread
graph state — there is no ContextVar. Source-agnostic: a tool is "deferred"
when it carries the ``deerflow_mcp`` metadata tag.
"""''',
    '''The agent sees deferred tool names in <available-deferred-tools> but cannot
call them until it fetches their full schema via the tool_search tool. The
deferred set rides on a build-time closure and promotion lives in per-thread
graph state — there is no ContextVar. Source-agnostic: a tool is "deferred"
when it carries the ``deerflow_mcp`` metadata tag.

PacGate patch (2026-10-17): appends the auto-promotion layer from deer-flow
v2.1.0 (``build_mcp_routing_middleware`` + ``get_mcp_routing_hints_prompt_section``).
The v2.0.0 base has only model-initiated discovery, which is why enabling
``tool_search`` on its own produced the 2026-09-12 "deferred, not promoted" loop —
nothing pre-seeded the schemas a request obviously needed. Everything above this
note is the live v2.0.0 file, unchanged.
"""''',
)

# 2. Widen the metadata import to include the routing predicate.
src = src.replace(
    "from deerflow.tools.mcp_metadata import is_mcp_tool",
    "from deerflow.tools.mcp_metadata import get_mcp_routing, is_mcp_tool",
)

assert "get_mcp_routing, is_mcp_tool" in src, "metadata import not widened"
assert "def build_mcp_routing_middleware" not in src, "append block already present"

APPEND = '''

# ── Routing-based auto-promotion (PR2) — ported from deer-flow v2.1.0 ──
#
# Model-initiated discovery alone was measured insufficient on this stack: on
# 2026-09-12 every model called MCP tools without promoting first, producing a
# "deferred, not promoted" loop that never reached write_file. This layer closes
# that hole by promoting the schemas a request obviously needs, for free, from
# operator-authored keywords — before the model is called, so no extra round-trip.

MAX_TOP_K_FALLBACK = 3


def _routing_priority(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _routing_keywords(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [keyword for keyword in (str(item).strip() for item in value) if keyword]


def build_mcp_routing_middleware(
    tools: Iterable[BaseTool],
    deferred_setup: DeferredToolSetup,
    *,
    top_k: int = MAX_TOP_K_FALLBACK,
) -> "AgentMiddleware | None":
    """Build auto-promotion middleware from the caller's deferred tools.

    Returns ``None`` — meaning "no auto-promotion needed" — when deferral is off,
    when the catalog is empty, or when no deferred tool carries usable routing
    metadata. The caller must then rely on model-initiated ``tool_search``.

    The returned middleware receives only a flat, serializable routing index: it
    holds no ``BaseTool`` objects, executes nothing, and filters nothing
    (``DeferredToolFilterMiddleware`` owns that).
    """
    if deferred_setup.catalog_hash is None or not deferred_setup.deferred_names:
        return None

    routing_index: dict[str, dict[str, Any]] = {}
    for candidate in tools:
        tool_name = getattr(candidate, "name", "")
        if tool_name not in deferred_setup.deferred_names:
            continue
        routing = get_mcp_routing(candidate)
        if routing is None or routing.get("mode") != "prefer":
            continue
        keywords = _routing_keywords(routing.get("keywords"))
        if not keywords:
            continue
        routing_index[str(tool_name)] = {
            "priority": _routing_priority(routing.get("priority", 0)),
            "keywords": keywords,
        }

    if not routing_index:
        logger.info(
            "MCP routing metadata absent: no deferred tool declares routing.mode='prefer' "
            "with non-empty keywords, so auto-promotion is inactive and the model must "
            "call tool_search itself.",
        )
        return None

    from deerflow.agents.middlewares.mcp_routing_middleware import McpRoutingMiddleware

    logger.info("MCP routing index built: %d tool(s) with keywords (top_k=%s)", len(routing_index), top_k)
    return McpRoutingMiddleware(routing_index, deferred_setup.catalog_hash, top_k)


def get_mcp_routing_hints_prompt_section(
    tools: Iterable[BaseTool],
    *,
    deferred_names: frozenset[str] = frozenset(),
) -> str:
    """Render <mcp_routing_hints> from MCP tools carrying routing metadata.

    When tool_search has deferred an MCP tool the hint must point the model at
    promotion first, otherwise it may try to call a schema hidden from the request.
    """
    hints: list[tuple[int, str, list[str]]] = []
    for candidate in tools:
        routing = get_mcp_routing(candidate)
        if routing is None or routing.get("mode") != "prefer":
            continue
        keywords = routing.get("keywords") or []
        if not keywords:
            continue
        hints.append(
            (
                int(routing.get("priority", 0)),
                candidate.name,
                [html.escape(str(keyword), quote=False) for keyword in keywords],
            )
        )

    if not hints:
        return ""

    lines = ["<mcp_routing_hints>"]
    for priority, tool_name, keywords in sorted(hints, key=lambda item: (-item[0], item[1])):
        esc_name = html.escape(tool_name, quote=False)
        joined = keywords[0] if len(keywords) == 1 else f"{', '.join(keywords[:-1])}, or {keywords[-1]}"
        lines.append(f"When the user's request involves {joined}:")
        if tool_name in deferred_names:
            lines.append(f"  use `tool_search` to fetch `{esc_name}`, then prefer that MCP tool.")
        else:
            lines.append(f"  prefer the `{esc_name}` tool.")
    lines.append("</mcp_routing_hints>")
    return "\\n".join(lines)
'''

# 3. The append needs html + Iterable + Any.
src = src.replace(
    "import hashlib\nimport json\nimport logging\nimport re",
    "import hashlib\nimport html\nimport json\nimport logging\nimport re",
)
src = src.replace(
    "from dataclasses import dataclass\nfrom functools import cached_property\nfrom typing import Annotated",
    "from collections.abc import Iterable\nfrom dataclasses import dataclass\nfrom functools import cached_property\nfrom typing import TYPE_CHECKING, Annotated, Any",
)
src = src.replace(
    "from deerflow.tools.mcp_metadata import get_mcp_routing, is_mcp_tool\n\nlogger",
    "from deerflow.tools.mcp_metadata import get_mcp_routing, is_mcp_tool\n\nif TYPE_CHECKING:\n    from langchain.agents.middleware import AgentMiddleware\n\nlogger",
)

src = src.rstrip("\n") + "\n" + APPEND

OUT.write_text(src, encoding="utf-8", newline="\n")

# validate
import ast  # noqa: E402

ast.parse(src)
print("written:", OUT.name, OUT.stat().st_size, "bytes")
print("has html import   :", "import html" in src)
print("has Any/Iterable  :", "Iterable" in src.split("logger = logging")[0])
print("has TYPE_CHECKING :", "TYPE_CHECKING" in src)
print("defs appended     :", src.count("def build_mcp_routing_middleware"), src.count("def get_mcp_routing_hints_prompt_section"))
print("live body intact  :", "def build_deferred_tool_setup" in src and "def assemble_deferred_tools" in src and "class DeferredToolCatalog" in src)
