"""Build patches/deer-flow-extensions-config.py: live v2.0.0 file + MCP routing config.

Generated rather than hand-written so the live file is preserved byte-for-byte and only
the additive routing block is inserted. The v2.1.0 file cannot be copied wholesale: it
imports `deerflow.constants`, which does not exist in the v2.0.0 image.
"""
import ast
import pathlib

LIVE = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\runtime\_port\live_config_extensions_config.py")
OUT = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\patches\deer-flow-extensions-config.py")

src = LIVE.read_text(encoding="utf-8")

# ── 1. docstring + future import + logging ──
old_head = '''"""Unified extensions configuration for MCP servers and skills."""

import json
import os
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from deerflow.config.runtime_paths import existing_project_file
'''
new_head = '''"""Unified extensions configuration for MCP servers and skills.

PacGate patch (2026-10-17): adds soft MCP routing hints (``McpRoutingConfig``,
``McpToolOverride``, ``resolve_effective_mcp_routing``). The v2.0.0 base has no routing
concept, which is why enabling ``tool_search`` alone produced the 2026-09-12
"deferred, not promoted" loop: the auto-promote path had no metadata to read, so nothing
pre-seeded the schemas a request obviously needed. Applied as three insertions onto the
live file; nothing else changed.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from deerflow.config.runtime_paths import existing_project_file

logger = logging.getLogger(__name__)
'''
assert old_head in src, "live head did not match"
src = src.replace(old_head, new_head, 1)

# ── 2. routing models + resolver, inserted before McpServerConfig ──
anchor = 'class McpServerConfig(BaseModel):\n    """Configuration for a single MCP server."""'
assert anchor in src, "McpServerConfig anchor not found"

ROUTING_BLOCK = '''class McpRoutingConfig(BaseModel):
    """Soft routing hints for MCP tool preference."""

    mode: Literal["off", "prefer"] = Field(
        default="off",
        description="Whether to emit prompt hints preferring this MCP tool for matching requests.",
    )
    priority: int = Field(
        default=0,
        description="Ordering key for routing hints. Higher values are rendered first.",
    )
    keywords: list[str] = Field(
        default_factory=list,
        description="Operator-authored keywords that describe when this MCP tool should be preferred.",
    )
    model_config = ConfigDict(extra="forbid")

    @field_validator("priority")
    @classmethod
    def _clamp_priority(cls, value: int) -> int:
        if value < 0:
            logger.warning("MCP routing priority %s is below 0; clamping to 0.", value)
            return 0
        if value > 100:
            logger.warning("MCP routing priority %s is above 100; clamping to 100.", value)
            return 100
        return value


class McpToolOverride(BaseModel):
    """Per-tool MCP configuration overrides."""

    routing: McpRoutingConfig = Field(default_factory=McpRoutingConfig)
    model_config = ConfigDict(extra="allow")


'''
src = src.replace(anchor, ROUTING_BLOCK + anchor, 1)

# ── 3. fields on McpServerConfig ──
old_field = '''    description: str = Field(default="", description="Human-readable description of what this MCP server provides")
    model_config = ConfigDict(extra="allow")

    @model_validator(mode="before")
    @classmethod
    def _accept_transport_alias(cls, data: Any) -> Any:'''
new_field = '''    description: str = Field(default="", description="Human-readable description of what this MCP server provides")
    routing: McpRoutingConfig = Field(default_factory=McpRoutingConfig, description="Soft routing hints for tools from this MCP server")
    tools: dict[str, McpToolOverride] = Field(default_factory=dict, description="Per-tool MCP configuration overrides, keyed by the server's raw tool name")
    model_config = ConfigDict(extra="allow")

    @model_validator(mode="before")
    @classmethod
    def _accept_transport_alias(cls, data: Any) -> Any:'''
assert old_field in src, "McpServerConfig field anchor not found"
src = src.replace(old_field, new_field, 1)

# ── 4. resolver after the class (needs McpServerConfig) ──
resolver_anchor = "\n\ndef get_extensions_config()"
assert resolver_anchor in src, "get_extensions_config anchor not found"
RESOLVER = '''


def resolve_effective_mcp_routing(server_config: McpServerConfig | None, original_tool_name: str) -> dict[str, Any]:
    """Merge server-level routing with per-tool overrides for one MCP tool.

    Keyed on the server's RAW tool name, not the prefixed name the adapter presents:
    tool names are prefixed at load time, so the durable binding must stay unprefixed.
    """
    if server_config is None:
        return McpRoutingConfig().model_dump(mode="json")

    effective = server_config.routing.model_dump(mode="json")
    override = server_config.tools.get(original_tool_name)
    if override is not None and "routing" in override.model_fields_set:
        effective.update(override.routing.model_dump(mode="json", exclude_unset=True))
    return effective


def get_extensions_config()'''
src = src.replace(resolver_anchor, RESOLVER, 1)

OUT.write_text(src, encoding="utf-8", newline="\n")
ast.parse(src)

print("written:", OUT.name, OUT.stat().st_size, "bytes")
print("McpRoutingConfig   :", src.count("class McpRoutingConfig"))
print("McpToolOverride    :", src.count("class McpToolOverride"))
print("resolver           :", src.count("def resolve_effective_mcp_routing"))
print("routing field      :", "routing: McpRoutingConfig = Field(" in src)
print("tools field        :", "tools: dict[str, McpToolOverride]" in src)
print("logger defined     :", "logger = logging.getLogger" in src)
print("no deerflow.constants:", "deerflow.constants" not in src)
print("live classes intact:", all(k in src for k in ("class McpOAuthConfig", "class SkillStateConfig", "class ExtensionsConfig", "def get_extensions_config", "def reload_extensions_config")))
