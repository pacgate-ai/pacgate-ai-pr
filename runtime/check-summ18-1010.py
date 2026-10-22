import sys
sys.path.insert(0, '/app/backend')

# The live middleware is DeerFlowSummarizationMiddleware (a SUBCLASS). Check its
# _should_summarize override - maybe it has extra gating.
import inspect
from deerflow.agents.lead_agent.agent import build_middlewares
from langchain_core.runnables import RunnableConfig

config = RunnableConfig(configurable={'thread_id': 'test', 'model_name': 'deepseek-v4.1-flash-cloud', 'thinking_enabled': False})
mws = build_middlewares(config, 'deepseek-v4.1-flash-cloud')
smw = [m for m in mws if 'Summar' in type(m).__name__][0]
cls = type(smw)
print('class:', cls.__name__, '| bases:', [b.__name__ for b in cls.__bases__])
print('has own _should_summarize:', '_should_summarize' in cls.__dict__)
print('has own before_model:', 'before_model' in cls.__dict__)
print('has own abefore_model:', 'abefore_model' in cls.__dict__)
for name in ['before_model', 'abefore_model', '_should_summarize', '_amaybe_summarize']:
    if name in cls.__dict__:
        print(f'--- {name} ---')
        print(inspect.getsource(cls.__dict__[name])[:1500])