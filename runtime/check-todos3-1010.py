import sqlite3, json

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()

tid = '630881f0-0c23-4ef9-ada7-e860c8033045'

# Scan ALL checkpoints of this thread for b'todos' in the checkpoint blob
cur.execute("SELECT checkpoint_id, checkpoint FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC", (tid,))
found = 0
scanned = 0
for cp_id, blob in cur.fetchall():
    scanned += 1
    if blob and b'todos' in blob:
        found += 1
        if found <= 2:
            idx = blob.find(b'todos')
            print(f"checkpoint {cp_id}: todos at {idx}")
            print("context:", blob[max(0,idx-60):idx+250])
print(f"\nscanned {scanned} checkpoints, todos found in {found}")

# Also check the writes table blob for todos
cur.execute("SELECT channel, value FROM writes WHERE thread_id=? AND channel NOT LIKE 'branch%' ORDER BY rowid DESC LIMIT 50", (tid,))
for ch, val in cur.fetchall():
    if val and b'todos' in val:
        print(f"\nWRITE channel={ch} contains todos")
        idx = val.find(b'todos')
        print("context:", val[max(0,idx-60):idx+250])
        break