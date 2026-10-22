import sys
sys.path.insert(0, '/app/backend')

# keep=(tokens, 4000) -> _find_token_based_cutoff. Check what it returns for the
# actual messages - if it returns 0 or None->safe_cutoff<=0, summarization skips.
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

cutoff = mw._determine_cutoff_index(messages)
print('cutoff index:', cutoff)
print('keep:', mw.keep)
print('model profile limits:', mw._get_profile_limits())
tok_cut = mw._find_token_based_cutoff(messages)
print('token_based_cutoff:', tok_cut)