import sys
sys.path.insert(0, '/app/backend')

# should_summarize=True with 8643 tokens > 5000 trigger. So WHY didn't it fire during the run?
# Check WHEN the trigger was crossed. The middleware runs before_model each step.
# Check the FIRST checkpoint's message count and token count
import sqlite3
from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer
from deerflow.agents.middlewares.summarization_middleware import SummarizationMiddleware
from deerflow.config import get_app_config
from deerflow.models.factory import create_chat_model

cfg = get_app_config()
s = cfg.summarization
model = create_chat_model(s.model_name)
mw = SummarizationMiddleware(
    model=model,
    model_name=s.model_name,
    trigger=[(t.type, t.value) for t in s.trigger],
    keep=(s.keep.type, s.keep.value),
    trim_tokens_to_summarize=s.trim_tokens_to_summarize,
)

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
ser = JsonPlusSerializer()
cur.execute("SELECT checkpoint_id, checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id ASC", (tid,))
for cp_id, blob in cur.fetchall():
    cp = ser.loads_typed(('msgpack', blob))
    messages = cp.get('channel_values', {}).get('messages', [])
    if not messages:
        continue
    total = mw.token_counter(messages)
    should = mw._should_summarize(messages, total)
    print(f'{cp_id[:13]} msgs={len(messages):3d} tokens={total:6d} should={should}')