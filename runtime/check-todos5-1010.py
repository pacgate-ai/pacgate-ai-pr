import sqlite3, json

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()

# Check if write_todos appears ANYWHERE in the whole checkpoints DB (3485 rows)
cur.execute("SELECT COUNT(*) FROM checkpoints WHERE checkpoint LIKE '%todos%'")
print("checkpoints containing 'todos' string:", cur.fetchone()[0])

# Check the writes table too
cur.execute("SELECT COUNT(*) FROM writes WHERE value LIKE '%todos%'")
print("writes containing 'todos':", cur.fetchone()[0])

# Check what tools the model actually called recently - look at run_events
conn2 = sqlite3.connect('/app/backend/.deer-flow/data/deerflow.db')
cur2 = conn2.cursor()
cur2.execute("SELECT DISTINCT event_type FROM run_events LIMIT 30")
print("\nrun_event types:", [r[0] for r in cur2.fetchall()])