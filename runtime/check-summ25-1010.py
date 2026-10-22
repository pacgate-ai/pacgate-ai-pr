import sys
sys.path.insert(0, '/app/backend')

# No summarizer exceptions in logs. The middleware ran, returned None.
# The ONLY remaining explanation: the middleware's before_model node was
# SKIPPED in the graph execution. The branch channel exists but maybe the
# branch was never TAKEN (versions_seen empty for that branch).
# Check versions_seen for the summarization branch in the last checkpoint
import sqlite3
from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
blob = cur.fetchone()[0]
ser = JsonPlusSerializer()
cp = ser.loads_typed(('msgpack', blob))
vs = cp.get('versions_seen', {})
for k in vs:
    if 'ummariz' in k:
        print('versions_seen for', k, ':', vs[k])
uv = cp.get('updated_channels', [])
print('updated_channels:', uv)
cv = cp.get('channel_versions', {})
summ_keys = [k for k in cv if 'ummariz' in k]
print('channel_versions summarization keys:', [(k, cv[k]) for k in summ_keys])