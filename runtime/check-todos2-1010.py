import sqlite3, json

# The real checkpoints DB
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
print("tables:", [r[0] for r in cur.fetchall()])

tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
cur.execute("SELECT checkpoint_id FROM checkpoints WHERE thread_id=? ORDER BY checkpoint_id DESC LIMIT 3", (tid,))
rows = cur.fetchall()
print("latest checkpoints:", rows)

if rows:
    cp = rows[0][0]
    cur.execute("PRAGMA table_info(checkpoints)")
    print("checkpoint cols:", [r[1] for r in cur.fetchall()])
    cur.execute("SELECT checkpoint FROM checkpoints WHERE thread_id=? AND checkpoint_id=?", (tid, cp))
    blob = cur.fetchone()[0]
    print("blob size:", len(blob) if blob else 0)
    if blob:
        idx = blob.find(b'todos')
        print("b'todos' at offset:", idx)
        if idx >= 0:
            print("context:", blob[max(0,idx-100):idx+300])
    cur.execute("SELECT DISTINCT channel FROM writes WHERE thread_id=?", (tid,))
    print("write channels:", [r[0] for r in cur.fetchall()])