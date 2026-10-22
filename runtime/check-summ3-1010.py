import sqlite3
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
# Empty writes = middleware ran but produced no state change = trigger NOT reached.
# Message tokens: the middleware counts message tokens. Input was 67-73k total,
# but ~32k is tools+system. So messages were ~35-41k tokens >> 5000 trigger.
# UNLESS the trigger counts differently. Let's check the live middleware state.
# Actually check: what did the middleware see? Look at the checkpoint blob for
# the summarization state key
cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
blob = cur.fetchone()[0]
for marker in [b'DeerFlowSummarization', b'summarization', b'trigger', b'should_summarize']:
    idx = blob.find(marker)
    print(marker, 'at', idx)
# Count messages in the thread
cur.execute("SELECT COUNT(*) FROM writes WHERE thread_id=? AND channel='messages'", (tid,))
print('message writes:', cur.fetchone()[0])