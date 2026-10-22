import sqlite3, json

conn = sqlite3.connect('/app/backend/.deer-flow/data/deerflow.db')
cur = conn.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [r[0] for r in cur.fetchall()]
print("tables:", tables)

# Find users
for t in tables:
    if 'user' in t.lower():
        cur.execute(f"SELECT * FROM {t} LIMIT 5")
        cols = [d[0] for d in cur.description]
        print(f"\n{t} cols:", cols)
        for row in cur.fetchall():
            print(" ", {c: (str(v)[:40]) for c, v in zip(cols, row)})

# Check the recent thread's values for todos
cur.execute("SELECT thread_id, created_at FROM threads_meta ORDER BY created_at DESC LIMIT 8")
print("\nrecent threads:")
threads = cur.fetchall()
for r in threads:
    print(" ", r)

# Check writes table channels (todos would appear as a state channel)
cur.execute("SELECT DISTINCT channel FROM writes")
print("\ndistinct write channels:")
for r in cur.fetchall():
    print(" ", r[0])

# Check the most recent thread's writes for todos channel
if threads:
    tid = threads[0][0]
    print(f"\nwrites for thread {tid}:")
    cur.execute("SELECT checkpoint_id, task_id, idx, channel FROM writes WHERE thread_id=? ORDER BY rowid DESC LIMIT 30", (tid,))
    for r in cur.fetchall():
        print(" ", r)