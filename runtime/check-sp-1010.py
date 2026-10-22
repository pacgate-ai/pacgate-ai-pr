import sys

sys.path.insert(0, "/app/backend")
sys.path.insert(0, "/app/backend/packages/harness")

from deerflow.agents.lead_agent.prompt import apply_prompt_template
from deerflow.config.app_config import get_app_config

cfg = get_app_config()
sp = apply_prompt_template(app_config=cfg)
print("system prompt chars:", len(sp))
i = sp.find("File Management")
print("File Management at char:", i, "of", len(sp))
print("MUST text present:", "you MUST use the" in sp)
