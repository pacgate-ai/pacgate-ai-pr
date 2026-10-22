import sqlite3

conn = sqlite3.connect("/app/backend/.deer-flow/data/deerflow.db")
cur = conn.cursor()
cur.execute("SELECT substr(last_ai_message,1,250) FROM runs WHERE run_id=?", ("65f9a41d-d99e-4cb9-be9c-8d20c47681d6",))
r = cur.fetchone()
print(r[0] if r else "none")
