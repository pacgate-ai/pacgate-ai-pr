"""Build patches/deer-flow-agent.py: live v2.0.0 lead agent + MCP routing wiring.

Wires ``McpRoutingMiddleware`` ahead of ``DeferredToolFilterMiddleware`` at both the
bootstrap and default build sites. Ordering is load-bearing and asserted downstream by
``assert_mcp_routing_before_deferred_filter``.
"""
import ast
import pathlib

LIVE = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\runtime\_port\live_agents_lead_agent_agent.py")
OUT = pathlib.Path(r"C:\Users\pacga\github-pr\pacgate-law\pacgate-ai\deploy\client-bundle\patches\deer-flow-agent.py")

src = LIVE.read_text(encoding="utf-8")

# ── 1. build_middlewares signature: accept the routing middleware ──
old_sig = """    deferred_setup=None,"""
new_sig = """    deferred_setup=None,
    mcp_routing_middleware=None,"""
if old_sig in src:
    src = src.replace(old_sig, new_sig, 1)
else:
    raise SystemExit("could not find the build_middlewares signature anchor")

# ── 2. install routing BEFORE the deferred filter ──
old_filter = """    # Hide deferred tool schemas from model binding until tool_search promotes them.
    # The deferred set + catalog hash come from the build-time setup (assembled
    # after tool-policy filtering); promotion is read from graph state.
    if deferred_setup is not None and deferred_setup.deferred_names:
        from deerflow.agents.middlewares.deferred_tool_filter_middleware import DeferredToolFilterMiddleware

        middlewares.append(DeferredToolFilterMiddleware(deferred_setup.deferred_names, deferred_setup.catalog_hash))"""
new_filter = """    # Auto-promote the schemas a request obviously needs, from operator-authored routing
    # keywords, BEFORE the model is called. This MUST be installed before the deferred
    # filter: assert_mcp_routing_before_deferred_filter raises if the order is reversed.
    #
    # Without this layer the deferred catalog has nothing to pre-seed from, and a model
    # that calls an MCP tool without promoting first gets a "deferred, not promoted" loop
    # (observed 2026-09-12, which is why tool_search was disabled).
    #
    # NOTE: build_middlewares may be called before `final_tools` exists at some sites, so
    # the middleware is built by the caller and passed in; None means "no routing metadata
    # configured", which is the honest degrade to model-initiated tool_search.
    if mcp_routing_middleware is not None:
        middlewares.append(mcp_routing_middleware)

    # Hide deferred tool schemas from model binding until tool_search promotes them.
    # The deferred set + catalog hash come from the build-time setup (assembled
    # after tool-policy filtering); promotion is read from graph state.
    if deferred_setup is not None and deferred_setup.deferred_names:
        from deerflow.agents.middlewares.deferred_tool_filter_middleware import DeferredToolFilterMiddleware

        middlewares.append(DeferredToolFilterMiddleware(deferred_setup.deferred_names, deferred_setup.catalog_hash))"""
assert old_filter in src, "deferred-filter install anchor not found"
src = src.replace(old_filter, new_filter, 1)

# ── 3. import the routing builders ──
old_import = "    from deerflow.tools.builtins.tool_search import assemble_deferred_tools\n"
new_import = (
    "    from deerflow.tools.builtins.tool_search import (\n"
    "        assemble_deferred_tools,\n"
    "        build_mcp_routing_middleware,\n"
    "    )\n"
)
assert old_import in src, "tool_search import anchor not found"
src = src.replace(old_import, new_import, 1)

# ── 4. build + pass the middleware at both build sites ──
old_call = """        final_tools, setup = assemble_deferred_tools(filtered, enabled=resolved_app_config.tool_search.enabled)
        return create_agent("""
new_call = """        final_tools, setup = assemble_deferred_tools(filtered, enabled=resolved_app_config.tool_search.enabled)
        setup_routing_middleware = build_mcp_routing_middleware(
            final_tools,
            setup,
            top_k=resolved_app_config.tool_search.auto_promote_top_k,
        )
        return create_agent("""
assert old_call in src, "bootstrap build site not found"
src = src.replace(old_call, new_call, 1)

old_call2 = """    final_tools, setup = assemble_deferred_tools(filtered, enabled=resolved_app_config.tool_search.enabled)
    return create_agent("""
new_call2 = """    final_tools, setup = assemble_deferred_tools(filtered, enabled=resolved_app_config.tool_search.enabled)
    setup_routing_middleware = build_mcp_routing_middleware(
        final_tools,
        setup,
        top_k=resolved_app_config.tool_search.auto_promote_top_k,
    )
    return create_agent("""
assert old_call2 in src, "default build site not found"
src = src.replace(old_call2, new_call2, 1)

# ── 5. pass it through at both build_middlewares call sites ──
old_pass = """                app_config=resolved_app_config,
                deferred_setup=setup,
            ),"""
new_pass = """                app_config=resolved_app_config,
                deferred_setup=setup,
                mcp_routing_middleware=setup_routing_middleware,
            ),"""
assert old_pass in src, "bootstrap pass-through not found"
src = src.replace(old_pass, new_pass, 1)

old_pass2 = """            app_config=resolved_app_config,
            deferred_setup=setup,
        ),"""
new_pass2 = """            app_config=resolved_app_config,
            deferred_setup=setup,
            mcp_routing_middleware=setup_routing_middleware,
        ),"""
assert old_pass2 in src, "default pass-through not found"
src = src.replace(old_pass2, new_pass2, 1)

OUT.write_text(src, encoding="utf-8", newline="\n")
ast.parse(src)

print("written:", OUT.name, OUT.stat().st_size, "bytes")
print("sig param   :", src.count("mcp_routing_middleware=None"))
print("install     :", src.count("if mcp_routing_middleware is not None:"))
print("build sites :", src.count("setup_routing_middleware = build_mcp_routing_middleware("))
print("pass-through:", src.count("mcp_routing_middleware=setup_routing_middleware,"))
print("import ok   :", "build_mcp_routing_middleware," in src)
print("order ok    :", src.index("mcp_routing_middleware is not None") < src.index("DeferredToolFilterMiddleware(deferred_setup.deferred_names"))
