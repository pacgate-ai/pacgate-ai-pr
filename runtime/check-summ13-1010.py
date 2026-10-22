import sys
sys.path.insert(0, '/app/backend')

# _create_summary returns EMPTY (len 0). Trace inside: _trim_messages_for_summary
# then get_buffer_string then model call. The model call returned empty content?
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
msgs_to_summ = messages[:cutoff]

trimmed = mw._trim_messages_for_summary(msgs_to_summ)
print('trimmed count:', len(trimmed) if trimmed else 0)
if trimmed:
    from langchain_core.messages import get_buffer_string
    formatted = get_buffer_string(trimmed)
    print('formatted len:', len(formatted))
    prompt = mw.summary_prompt.format(messages=formatted).rstrip()
    print('prompt len:', len(prompt))
    # Direct model call
    resp = model.invoke(prompt)
    print('model response type:', type(resp).__name__)
    print('content len:', len(resp.content) if resp.content else 0)
    print('content head:', repr(resp.content)[:300])
    print('finish:', resp.response_metadata.get('finish_reason'))
    print('usage:', resp.usage_metadata)