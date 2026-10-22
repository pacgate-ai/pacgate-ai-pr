# Validate deer-flow-config.yaml with the container's venv python (has yaml)
import yaml, sys
p = "/app/backend/config.yaml"
d = yaml.safe_load(open(p, encoding="utf-8"))
names = [m["name"] for m in d["models"]]
print("models:", names)
print("default(first):", names[0])
print("routing.local:", d["model_routing"]["local_model"])
print("routing.cloud:", d["model_routing"]["cloud_model"])
print("memory.model_name:", d["memory"]["model_name"])
print("summarization.model_name:", d["summarization"]["model_name"])
print("summarization.enabled:", d["summarization"]["enabled"])
# every model_name referenced must exist in models
refs = [d["model_routing"]["local_model"], d["model_routing"]["cloud_model"], d["memory"]["model_name"], d["summarization"]["model_name"]]
missing = [r for r in refs if r not in names]
print("missing refs:", missing or "NONE")
# tags used
tags = {m["name"]: m["model"] for m in d["models"]}
print("tags:", tags)
