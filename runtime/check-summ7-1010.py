import sys
sys.path.insert(0, '/app/backend')

# Read messages directly from the checkpoint DB via langgraph serializer
import sqlite3
from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
blob = cur.fetchone()[0]

ser = JsonPlusSerializer()
cp = ser.loads_typed(('msgpack', blob))
print('checkpoint keys:', list(cp.keys()) if isinstance(cp, dict) else type(cp))
channel_values = cp.get('channel_values', {}) if isinstance(cp, dict) else {}
print('channel_values keys:', list(channel_values.keys()))
messages = channel_values.get('messages', [])
print('message count:', len(messages))

from deerflow.agents.middlewares.summarization_middleware import SummarizationMiddleware
from deerflow.config import get_app_config
cfg = get_app_config()
s = cfg.summarization
# Build the summarizer model the same way the agent does
from deerflow.models.factory import create_chat_model
model = create_chat_model(s.model_name)
mw = SummarizationMiddleware(
    model=model,
    model_name=s.model_name,
    trigger=[(t.type, t.value) for t in s.trigger],
    keep=(s.keep.type, s.keep.value),
    trim_tokens_to_summarize=s.trim_tokens_to_summarize,
)
total = mw.token_counter(messages)
print('middleware token_counter(messages):', total)
print('trigger:', mw._trigger_conditions)
print('should_summarize:', mw._should_summarize(messages, total))