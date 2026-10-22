import sys

sys.path.insert(0, "/app/backend")
sys.path.insert(0, "/app/backend/packages/harness")

from deerflow.tools.tools import get_available_tools
from deerflow.config.app_config import get_app_config

cfg = get_app_config()
tools = get_available_tools(app_config=cfg)
names = [t.name for t in tools]
print(f"total tools available: {len(names)}")
print("read_file bound:", "read_file" in names)
print("grep bound:", "grep" in names)
print("first 12:", names[:12])
