import sys
sys.path.insert(0, '/app/backend')

# ROOT CAUSE FOUND: the summarizer model burns ALL 4096 output tokens on
# INVISIBLE REASONING (finish_reason=length, content=''). Same reasoning-burn
# defect as the cloud models had! nemotron-3.5-lightning:30b-a3b has thinking
# enabled by default and the summarizer call doesn't suppress it.
# Verify: check if the response has reasoning content
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

resp = model.invoke(prompt)
print('content:', repr(resp.content)[:100])
print('additional_kwargs keys:', list(resp.additional_kwargs.keys()))
rc = resp.additional_kwargs.get('reasoning_content')
print('reasoning_content len:', len(rc) if rc else 0)
if rc:
    print('reasoning head:', rc[:300])
print('finish:', resp.response_metadata.get('finish_reason'))