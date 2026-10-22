import sys
sys.path.insert(0, '/app/backend')

# Run the FULL _maybe_summarize path synchronously to see where it stops
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
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
blob = cur.fetchone()[0]
ser = JsonPlusSerializer()
cp = ser.loads_typed(('msgpack', blob))
messages = cp['channel_values']['messages']

# Call _create_summary directly with the cutoff partition
cutoff = mw._determine_cutoff_index(messages)
msgs_to_summ = messages[:cutoff]
print('calling _create_summary with', len(msgs_to_summ), 'messages...')
try:
    summary = mw._create_summary(msgs_to_summ)
    print('SUMMARY OK, len:', len(summary) if summary else 0)
    if summary:
        print('head:', summary[:300])
except Exception as e:
    import traceback
    traceback.print_exc()