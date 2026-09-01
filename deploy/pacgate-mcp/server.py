"""Pacgate MCP server — exposes pacgate-api's RAG + legal connector search as MCP tools.

This is a standard MCP HTTP (streamable) server that deer-flow consumes the same
way it consumes `openviking` (via `mcpServers` in `extensions_config.json`).

It reuses pacgate-api's own HTTP endpoints so deer-flow never sees credentials —
auth happens inside pacgate-api. The MCP server authenticates once at startup
using `PACGATE_API_EMAIL`/`PACGATE_API_PASSWORD` (or `PACGATE_JWT_TOKEN`) and
forwards a Bearer token on every call.

Exposed tools:
    pacgate_kb_search        — query the internal per-matter RAG store
                              (GET /api/kb/search?matter_id=&q=&top_k=&max_data_level=)
    pacgate_connector_search — query external legal databases
                              (GET /api/search?q=&jurisdiction=&doc_type=&limit=&connector=)
    pacgate_list_connectors  — list available legal data source connectors
                              (GET /api/search/connectors)
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

logging.basicConfig(
    level=os.environ.get("PACGATE_MCP_LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)
logger = logging.getLogger("pacgate_mcp")

# Bind the streamable HTTP transport on 0.0.0.0 so the deer-flow container on
# the compose network can reach it. Host must not stay 127.0.0.1.
mcp = FastMCP(
    "pacgate",
    host="0.0.0.0",
    port=int(os.environ.get("PACGATE_MCP_PORT", "8000")),
)


class PacgateApi:
    """Minimal authenticated client for pacgate-api."""

    def __init__(self) -> None:
        self.base_url = os.environ.get(
            "PACGATE_API_URL", "http://pacgate-api:8080"
        ).rstrip("/")
        self.email = os.environ.get("PACGATE_API_EMAIL", "")
        self.password = os.environ.get("PACGATE_API_PASSWORD", "")
        self.jwt_token = os.environ.get("PACGATE_JWT_TOKEN", "")
        self.timeout = float(os.environ.get("PACGATE_MCP_TIMEOUT", "60"))
        self._client = httpx.Client(timeout=self.timeout)
        if not self.jwt_token and self.email and self.password:
            self.jwt_token = self._login()

    def _login(self) -> str:
        resp = self._client.post(
            f"{self.base_url}/api/auth/login",
            json={"email": self.email, "password": self.password},
            headers={"Content-Type": "application/json"},
        )
        resp.raise_for_status()
        token = resp.json().get("token", "")
        if not token:
            raise ValueError("pacgate-api login did not return a token")
        logger.info("Authenticated with pacgate-api")
        return token

    def _headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.jwt_token:
            headers["Authorization"] = f"Bearer {self.jwt_token}"
        return headers

    def get(self, path: str, params: dict[str, Any] | None = None) -> httpx.Response:
        return self._client.get(
            f"{self.base_url}{path}", params=params, headers=self._headers()
        )


# Instantiate lazily so the MCP server can start even if pacgate-api is not yet
# reachable; auth is refreshed on first tool call if needed.
_client: PacgateApi | None = None


def get_client() -> PacgateApi:
    global _client
    if _client is None:
        _client = PacgateApi()
    return _client


def _handle_error(resp: httpx.Response) -> None:
    if resp.status_code >= 400:
        raise RuntimeError(
            f"pacgate-api error {resp.status_code}: {resp.text}"
        )


@mcp.tool()
def pacgate_kb_search(
    query: str,
    matter_id: str,
    top_k: int = 5,
    jurisdiction: str | None = None,
    source_level: str | None = None,
    max_data_level: str = "T3",
) -> str:
    """Search pacgate's internal per-matter knowledge base (RAG).

    Retrieves chunks of law-firm documents relevant to a matter using hybrid
    semantic + keyword search, filtered by the T1-T4 data classification level.

    Args:
        query: The search keywords / natural-language question.
        matter_id: The UUID of the matter to search within.
        top_k: Maximum number of chunks to return (default 5).
        jurisdiction: Optional filter, e.g. "ChinaMainland" or "UnitedStates".
        source_level: Optional source-level filter (e.g. "AuthorityVerified").
        max_data_level: Max data classification T1-T4 (default T3; excludes T4).
    """
    client = get_client()
    params: dict[str, Any] = {
        "q": query,
        "matter_id": matter_id,
        "top_k": top_k,
    }
    if jurisdiction:
        params["jurisdiction"] = jurisdiction
    if source_level:
        params["source_level"] = source_level
    if max_data_level:
        params["max_data_level"] = max_data_level

    resp = client.get("/api/kb/search", params=params)
    _handle_error(resp)
    results = resp.json()
    return json.dumps(results, ensure_ascii=False, indent=2)


@mcp.tool()
def pacgate_connector_search(
    query: str,
    jurisdiction: str | None = None,
    doc_type: str | None = None,
    limit: int = 10,
    connector: str | None = None,
    data_level: str | None = None,
) -> str:
    """Search external legal databases (元典, 北大法宝, 企查查, CourtListener, SEC EDGAR, ...).

    Fans out across all available legal data source connectors and returns
    matching laws, cases, and filings.

    Args:
        query: The search keywords (e.g. a legal term or company name).
        jurisdiction: Optional filter, e.g. "ChinaMainland" or "UnitedStates".
        doc_type: Optional document type filter (law, case, regulation, ...).
        limit: Maximum results per connector (default 10).
        connector: Optional: restrict to a single connector by name.
        data_level: Optional data classification tag T1-T4 (audit only).
    """
    client = get_client()
    params: dict[str, Any] = {"q": query, "limit": limit}
    if jurisdiction:
        params["jurisdiction"] = jurisdiction
    if doc_type:
        params["doc_type"] = doc_type
    if connector:
        params["connector"] = connector
    if data_level:
        params["data_level"] = data_level

    resp = client.get("/api/search", params=params)
    _handle_error(resp)
    results = resp.json()
    return json.dumps(results, ensure_ascii=False, indent=2)


@mcp.tool()
def pacgate_list_connectors() -> str:
    """List the legal data source connectors available to pacgate.

    Returns each connector's name, display name, and availability so you know
    which external databases you can search.
    """
    client = get_client()
    resp = client.get("/api/search/connectors")
    _handle_error(resp)
    results = resp.json()
    return json.dumps(results, ensure_ascii=False, indent=2)


def main() -> None:
    port = int(os.environ.get("PACGATE_MCP_PORT", "8000"))
    logger.info("Starting pacgate MCP server on :%s", port)
    # Tools are registered on the module-level `mcp` via @mcp.tool().
    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
