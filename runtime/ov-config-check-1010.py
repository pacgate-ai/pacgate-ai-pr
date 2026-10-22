import json

cfg = json.load(open("/app/deer-flow-extensions-config.json"))
ov = cfg.get("mcpServers", {}).get("openviking", {})
print("openviking keys:", list(ov.keys()))
print("type:", ov.get("type"))
print("url:", ov.get("url"))
print("command:", ov.get("command"), ov.get("args"))
env = ov.get("env", {})
print("env keys:", list(env.keys()))
for k, v in env.items():
    if "key" in k.lower() or "token" in k.lower():
        print(f"  {k}: {v[:12]}... (len={len(v)})")
