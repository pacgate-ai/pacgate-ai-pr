# The user was created against a DIFFERENT DB path. Check which DB the gateway uses.
# The WAL file is being written - the gateway uses this DB. The user WAS created
# (in-process script used the same path). But the login failed with 401.
# Check if the user exists via the WAL - read with WAL mode
import sqlite3
conn = sqlite3.connect('file:/app/backend/.deer-flow/data/deerflow.db?mode=ro', uri=True)
cur = conn.cursor()
cur.execute("SELECT email, substr(password_hash,1,40) FROM users")
for r in cur.fetchall():
    print(r)
print('done')
