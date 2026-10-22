import json
import sys
import urllib.request

sys.path.insert(0, "/app/backend/.venv/lib/python3.12/site-packages")

import yaml

cfg = yaml.safe_load(open("/app/backend/config.yaml"))

# 1. Model picker roster (what /api/models serves)
print("=== MODEL PICKER ROSTER (config.yaml models:) ===")
for m in cfg.get("models", []):
    print(f"  {m['name']:42s} -> {m.get('model', '?'):38s} max_tokens={m.get('max_tokens', '-')} thinking={m.get('supports_thinking', False)}")

# 2. Model routing (escalation)
mr = cfg.get("model_routing", {})
print("\n=== MODEL ROUTING ===")
print(f"  enabled: {mr.get('enabled')}")
for k in ("local_model", "cloud_model", "escalation", "tool_count_threshold"):
    if k in mr:
        print(f"  {k}: {mr[k]}")

# 3. Summarization tuning
s = cfg.get("summarization", {})
print("\n=== SUMMARIZATION TUNING ===")
print(f"  enabled: {s.get('enabled')} model: {s.get('model_name')}")
print(f"  trigger: {s.get('trigger')} keep: {s.get('keep')}")

# 4. Memory tuning
mem = cfg.get("memory", {})
print("\n=== MEMORY TUNING ===")
print(f"  storage_class: {mem.get('storage_class')}")
print(f"  model_name: {mem.get('model_name')}")
for k in mem:
    if k not in ("storage_class", "model_name"):
        v = mem[k]
        if not isinstance(v, (dict, list)):
            print(f"  {k}: {v}")

# 5. Verify each configured model tag exists in Ollama
print("\n=== OLLAMA TAG AVAILABILITY ===")
try:
    req = urllib.request.Request("http://host.docker.internal:11434/api/tags")
    tags = json.loads(urllib.request.urlopen(req, timeout=10).read())
    installed = {t["name"] for t in tags["models"]}
    for m in cfg.get("models", []):
        tag = m.get("model", "")
        ok = tag in installed
        print(f"  {'OK ' if ok else 'MISSING'} {tag}")
except Exception as e:
    print(f"  ollama check failed: {e}")
