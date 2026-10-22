import sys
sys.path.insert(0, '/app/backend')

# 3/3 success now. But the LIVE run failed with finish=length. The difference:
# during the live run, nemotron was SHARING the runner with the chat model
# (same tag) and the KV cache was thrashing. OR the prompt was different.
# KEY INSIGHT: the middleware DID fire during the live run? No - 0 summary markers.
# Wait - the writes for the summarization channel were EMPTY (size 0) which means
# the middleware returned None (no state change). But should=True at every step...
# UNLESS the middleware that's actually wired is DIFFERENT from what I built.
# Check the LIVE middleware instance via the agent graph.
from deerflow.agents.lead_agent.agent import build_middlewares
from langchain_core.runnables import RunnableConfig
import inspect
sig = inspect.signature(build_middlewares)
print('build_middlewares params:', list(sig.parameters.keys()))