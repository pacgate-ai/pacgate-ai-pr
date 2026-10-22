import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute(
    "SELECT run_id, status, model_name, error, created_at FROM runs "
    "WHERE thread_id LIKE '5a0b52fe%' ORDER BY created_at"
)
for r in cur.fetchall():
    print(r[0][:8], r[1], r[2], "| err:", (r[3] or "")[:50], "|", r[4][:19])
