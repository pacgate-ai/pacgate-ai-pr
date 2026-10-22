import sys
sys.path.insert(0, '/app/backend')

# Build the LIVE middleware chain exactly as the agent does and inspect the
# summarization middleware instance
from deerflow.agents.lead_agent.agent import build_middlewares
from langchain_core.runnables import RunnableConfig

config = RunnableConfig(configurable={'thread_id': 'test', 'model_name': 'deepseek-v4.1-flash-cloud', 'thinking_enabled': False})
mws = build_middlewares(config, 'deepseek-v4.1-flash-cloud')
for m in mws:
    name = type(m).__name__
    if 'Summar' in name:
        print('FOUND live summarization middleware:', name)
        print('  trigger:', getattr(m, '_trigger_conditions', None))
        print('  keep:', getattr(m, 'keep', None))
        print('  model:', type(getattr(m, 'model', None)).__name__, getattr(m.model, 'model_name', None) if hasattr(m, 'model') else None)
        tc = getattr(m, 'token_counter', None)
        print('  token_counter:', tc)
    else:
        print('middleware:', name)