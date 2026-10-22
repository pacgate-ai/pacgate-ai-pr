import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute(
    "SELECT run_id, model_name, status, substr(last_ai_message, 1, 150) FROM runs "
    "WHERE first_human_message LIKE '%uploaded_files%' AND last_ai_message IS NOT NULL "
    "ORDER BY created_at DESC LIMIT 12"
)
for r in cur.fetchall():
    print(r[0][:8], (r[1] or "?")[:28], r[2], "|", (r[3] or "").replace("\n", " ")[:110])
