import sys
sys.path.insert(0, '/app/backend')

# FOUND IT: should=True but cutoff=0 -> "if cutoff_index <= 0: return None"
# The cutoff is 0 because keep=(tokens,4000) and _find_token_based_cutoff
# returns 0 when the LAST 4000 tokens cover ALL messages (i.e. there's nothing
# to summarize after keeping 4000 tokens of recent history).
# With only 3 messages at 2667 tokens, keep=4000 covers everything -> cutoff=0.
# As messages grew to 8643 tokens, cutoff should become >0... but the last
# checkpoint showed cutoff=5. So summarization SHOULD have fired later.
# Unless... the middleware only runs BEFORE the model call, and by the time
# cutoff>0 the run had already ended. Let me check the checkpoint where
# cutoff first became >0
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
first_positive = None
for cp_id, blob in cur.fetchall():
    cp = ser.loads_typed(('msgpack', blob))
    messages = cp['channel_values'].get('messages', [])
    if not messages:
        continue
    total = smw.token_counter(messages)
    if smw._should_summarize(messages, total):
        cutoff = smw._determine_cutoff_index(messages)
        if cutoff > 0 and first_positive is None:
            first_positive = (cp_id, len(messages), total, cutoff)
print('first checkpoint with cutoff>0:', first_positive)