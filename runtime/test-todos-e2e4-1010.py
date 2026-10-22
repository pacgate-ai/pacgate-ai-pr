# Two DBs exist. The gateway (CWD=/app/backend) uses /app/backend/.deer-flow/data/deerflow.db
# My script (CWD=/app) created the user in /app/.deer-flow/data/deerflow.db
import sqlite3
conn = sqlite3.connect('/app/.deer-flow/data/deerflow.db')
cur = conn.cursor()
cur.execute("SELECT email FROM users")
print('wrong-db users:', [r[0] for r in cur.fetchall()])