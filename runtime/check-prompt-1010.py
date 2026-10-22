import sys

sys.path.insert(0, "/app/backend")
sys.path.insert(0, "/app/backend/packages/harness")

import deerflow.agents.lead_agent.prompt as p

print("module file:", p.__file__)
src = open(p.__file__, encoding="utf-8").read()
print("has MUST text:", "you MUST use the" in src)
