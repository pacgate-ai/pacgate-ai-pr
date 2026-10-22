import json
import re
import time
import urllib.request

cfg = json.load(open("/app/deer-flow-extensions-config.json"))
ov = cfg.get("mcpServers", {}).get("openviking", {})
base_headers = dict(ov.get("headers", {}))
url = ov.get("url") or "http://openviking:1933/mcp"


def call(payload, sid=None):
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    headers.update(base_headers)
    if sid:
        headers["mcp-session-id"] = sid
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=headers)
    r = urllib.request.urlopen(req, timeout=60)
    d = r.read().decode()
    m = re.search(r"data: (.*)", d)
    return (r.headers.get("mcp-session-id"), json.loads(m.group(1)) if m else None)


t0 = time.time()
sid, init = call({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "audit", "version": "1.0"}}})
t1 = time.time()
_, h = call({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "health", "arguments": {}}}, sid)
t2 = time.time()
htext = h["result"]["content"][0]["text"] if h else "?"
print(f"init: {int((t1-t0)*1000)}ms | health: {int((t2-t1)*1000)}ms | {htext[:100]}")

# remember lane (async extraction)
marker = f"AUDIT-MARKER-1010-{int(time.time())}"
fact = f"The audit token {marker} refers to the Qing dynasty legal code review."
_, rem = call({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "remember", "arguments": {"messages": [{"role": "user", "content": fact}]}}}, sid)
t3 = time.time()
remtext = rem["result"]["content"][0]["text"] if rem else "?"
print(f"remember: {int((t3-t2)*1000)}ms | {remtext[:80]}")
print(f"MARKER={marker}")
