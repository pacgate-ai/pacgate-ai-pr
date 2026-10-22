import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute(
    "SELECT run_id, status, substr(last_ai_message,1,60) FROM runs "
    "WHERE thread_id=? ORDER BY created_at",
    ("c3506d3b-67f9-4976-a4d3-db0b2c321c74",),
)
for r in cur.fetchall():
    print(r[0][:8], r[1], "|", r[2])
