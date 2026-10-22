from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from langchain_core.messages import HumanMessage

ORIGINAL_USER_CONTENT_KEY = "original_user_content"

# PacGate patch (2026-10-17): ``is_real_user_message`` and SUMMARY_MESSAGE_NAME were
# added for the deferred-tool routing port. The v2.0.0 base shipped only
# ``message_content_to_text`` and ``get_original_user_content_text``; the v2.1.0
# McpRoutingMiddleware imports ``is_real_user_message`` to avoid letting
# middleware-injected hidden HumanMessages or summarization markers drive
# keyword-based MCP promotion.
SUMMARY_MESSAGE_NAME = "summary"


def message_content_to_text(content: Any) -> str:
    """Extract text from LangChain message content shapes."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                text = item.get("text")
                if isinstance(text, str):
                    parts.append(text)
        return "\n".join(part for part in parts if part)
    return str(content)


def get_original_user_content_text(content: Any, additional_kwargs: Mapping[str, Any] | None) -> str:
    """Return pre-middleware user text when available, otherwise content text."""
    original_content = (additional_kwargs or {}).get(ORIGINAL_USER_CONTENT_KEY)
    if isinstance(original_content, str):
        return original_content
    return message_content_to_text(content)


def is_real_user_message(message: object) -> bool:
    """Return whether ``message`` is a real user-authored HumanMessage.

    Middleware-injected hidden HumanMessages and summarization markers should not
    drive user-intent features such as slash-skill activation or MCP routing.
    """
    if not isinstance(message, HumanMessage):
        return False
    if message.name == SUMMARY_MESSAGE_NAME:
        return False
    if message.additional_kwargs.get("hide_from_ui"):
        return False
    return True
