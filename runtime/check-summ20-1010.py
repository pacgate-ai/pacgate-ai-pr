import sys
sys.path.insert(0, '/app/backend')

# CRITICAL FINDING: the live middleware DOES summarize when invoked directly
# (20 new messages = summary + preserved). So the middleware WORKS.
# But during the live run it returned None every time. The difference must be
# the STATE the middleware sees during the run. The gateway's graph state may
# differ from the checkpoint's channel_values.
# KEY QUESTION: was the summarization middleware even REACHED during the run?
# The writes showed 'branch:to:DeerFlowSummarizationMiddleware.before_model'
# with EMPTY values - meaning the node ran but wrote nothing.
# Wait - empty writes with should=True means _maybe_summarize returned None.
# But we just proved it returns 20 messages with the same state!
# UNLESS the state during the run had FEWER messages (the run was still growing).
# Check the EARLIEST checkpoints - the first ones with should=True
import sqlite3
from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer
from deerflow.agents.lead_agent.agent import build_middlewares
from langchain_core.runnables import RunnableConfig

config = RunnableConfig(configurable={'thread_id': 'test', 'model_name': 'deepseek-v4.1-flash-cloud', 'thinking_enabled': False})
mws = build_middlewares(config, 'deepseek-v4.1-flash-cloud')
smw = [m for m in mws if 'Summar' in type(m).__name__][0]

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
ser = JsonPlusSerializer()
cur.execute("SELECT checkpoint_id, checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id ASC", (tid,))
rows = cur.fetchall()
print('total checkpoints:', len(rows))
# Show the first 10 with messages
shown = 0
for cp_id, blob in rows:
    cp = ser.loads_typed(('msgpack', blob))
    messages = cp['channel_values'].get('messages', [])
    if not messages:
        continue
    total = smw.token_counter(messages)
    should = smw._should_summarize(messages, total)
    cutoff = smw._determine_cutoff_index(messages)
    if shown < 12:
        print(f'{cp_id[:13]} msgs={len(messages):3d} tokens={total:6d} should={should} cutoff={cutoff}')
        shown += 1