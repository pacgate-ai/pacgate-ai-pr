import sqlite3, json, zlib

# Read the checkpoint blob directly and decode the state to see channel values
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()

tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
cur.execute("SELECT checkpoint_id, type, checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 1", (tid,))
cp_id, cp_type, blob = cur.fetchone()
print('latest checkpoint:', cp_id, 'type:', cp_type, 'size:', len(blob))

# The checkpoint blob is msgpack-encoded. Try to find the channel names inside.
# Look for 'title' channel to understand the structure
for marker in [b'title', b'artifacts', b'messages', b'thread_data']:
    idx = blob.find(marker)
    print(f'{marker}: offset {idx}')

# Check the metadata column for the run context (mode)
cur.execute("SELECT metadata FROM checkpoints WHERE thread_id=? AND checkpoint_id=?", (tid, cp_id))
meta_blob = cur.fetchone()[0]
if meta_blob:
    try:
        meta = json.loads(meta_blob)
        print('\nmetadata keys:', list(meta.keys()))
        print(json.dumps(meta, ensure_ascii=False, indent=1)[:1500])
    except Exception as e:
        print('metadata not json:', meta_blob[:200])