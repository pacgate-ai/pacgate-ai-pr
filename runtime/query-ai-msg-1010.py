import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute("SELECT last_ai_message FROM runs WHERE run_id LIKE 'ef4969ba%'")
row = cur.fetchone()
print((row[0] or "")[:600] if row else "none")
