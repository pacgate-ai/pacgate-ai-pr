import sys

sys.path.insert(0, "/app/backend")
sys.path.insert(0, "/app/backend/packages/harness")

from deerflow.tools.tools import get_available_tools
from deerflow.skills.tool_policy import filter_tools_by_skill_allowed_tools
from deerflow.agents.lead_agent.agent import _load_enabled_skills_for_tool_policy
from deerflow.config.app_config import get_app_config

cfg = get_app_config()
tools = get_available_tools(app_config=cfg)
print(f"available: {len(tools)}, read_file in: {any(t.name == 'read_file' for t in tools)}")

skills = _load_enabled_skills_for_tool_policy(set(), app_config=cfg)
print(f"skills loaded for policy: {len(skills) if skills else 0}")
filtered = filter_tools_by_skill_allowed_tools(tools, skills or [])
print(f"after policy filter: {len(filtered)}, read_file in: {any(t.name == 'read_file' for t in filtered)}")

# check the description the model would see for read_file
rf = next((t for t in filtered if t.name == "read_file"), None)
if rf:
    print("read_file description head:", (rf.description or "")[:120])
else:
    print("read_file NOT in filtered set")
