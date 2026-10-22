import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute(
    "SELECT run_id, status, model_name, error, created_at, updated_at FROM runs "
    "WHERE created_at > '2026-10-10 09:20' ORDER BY created_at DESC LIMIT 10"
)
for r in cur.fetchall():
    print(r[0][:8], r[1], r[2], "| err:", (r[3] or "")[:40], "|", r[4][:19], "->", (r[5] or "")[11:19])
