import sys
sys.path.insert(0, '/app/backend')

# INTERESTING: this time it worked (finish=stop, content present). The earlier
# failure (finish=length, content='') is INTERMITTENT - nemotron sometimes burns
# the whole budget on reasoning. This is a nondeterministic reasoning-burn.
# Run the same call 3x to measure the failure rate.
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
trimmed = mw._trim_messages_for_summary(messages[:cutoff])
from langchain_core.messages import get_buffer_string
formatted = get_buffer_string(trimmed)
prompt = mw.summary_prompt.format(messages=formatted).rstrip()

import time
for i in range(3):
    t0 = time.time()
    resp = model.invoke(prompt)
    u = resp.usage_metadata or {}
    print(f'run{i}: content_len={len(resp.content or "")} finish={resp.response_metadata.get("finish_reason")} out={u.get("output_tokens")} elapsed={time.time()-t0:.1f}s')