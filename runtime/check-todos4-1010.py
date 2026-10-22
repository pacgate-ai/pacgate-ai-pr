import sqlite3, json

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()

# Scan ALL threads' checkpoints for b'write_todos' (the tool call) - did ANY thread ever use todos?
cur.execute("SELECT COUNT(*) FROM checkpoints")
total = cur.fetchone()[0]
print("total checkpoints:", total)

cur.execute("SELECT thread_id, checkpoint_id, checkpoint FROM checkpoints ORDER BY rowid DESC LIMIT 400")
found_threads = set()
for tid, cp_id, blob in cur.fetchall():
    if blob and (b'write_todos' in blob or b'todos' in blob):
        found_threads.add(tid)
print("threads (of last 400 cps) containing todos/write_todos:", len(found_threads))
for t in list(found_threads)[:5]:
    print(" ", t)

# Check if write_todos tool was ever registered - check the tools table or run_events
conn2 = sqlite3.connect('/app/backend/.deer-flow/data/deerflow.db')
cur2 = conn2.cursor()
cur2.execute("SELECT name FROM sqlite_master WHERE type='table'")
print("\ndeerflow.db tables:", [r[0] for r in cur2.fetchall()])
cur2.execute("PRAGMA table_info(run_events)")
print("run_events cols:", [r[1] for r in cur2.fetchall()])