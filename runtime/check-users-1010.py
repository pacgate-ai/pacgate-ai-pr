import sqlite3

conn = sqlite3.connect('/app/backend/.deer-flow/data/deerflow.db')
cur = conn.cursor()
cur.execute("SELECT email, substr(password_hash, 1, 30), system_role FROM users")
for r in cur.fetchall():
    print(r)