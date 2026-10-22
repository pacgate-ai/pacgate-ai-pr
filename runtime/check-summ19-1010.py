import sys
sys.path.insert(0, '/app/backend')

# The subclass overrides _amaybe_summarize with _partition_with_skill_rescue.
# But the parent's _maybe_summarize (sync) uses _partition_messages.
# The gateway runs ASYNC (abefore_model). Let me run the LIVE middleware's
# _amaybe_summarize against the real thread state and see what happens.
import sqlite3, asyncio
from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer
from deerflow.agents.lead_agent.agent import build_middlewares
from langchain_core.runnables import RunnableConfig

config = RunnableConfig(configurable={'thread_id': 'test', 'model_name': 'deepseek-v4.1-flash-cloud', 'thinking_enabled': False})
mws = build_middlewares(config, 'deepseek-v4.1-flash-cloud')
smw = [m for m in mws if 'Summar' in type(m).__name__][0]

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
blob = cur.fetchone()[0]
ser = JsonPlusSerializer()
cp = ser.loads_typed(('msgpack', blob))
messages = cp['channel_values']['messages']
print('messages:', len(messages))

# token count with the LIVE counter
total = smw.token_counter(messages)
print('live token_counter:', total)
print('should:', smw._should_summarize(messages, total))

class FakeRuntime:
    context = {'thread_id': tid}

async def main():
    result = await smw._amaybe_summarize({'messages': messages}, FakeRuntime())
    print('RESULT:', 'None (no summarization)' if result is None else f'{len(result.get("messages", []))} new messages')
    if result:
        for m in result['messages'][:3]:
            print('  ', type(m).__name__, getattr(m, 'content', '')[:100])

asyncio.run(main())