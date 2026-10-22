import sqlite3, json

conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()

# Check the mode distribution across recent checkpoints - what modes do users run with?
cur.execute("""
    SELECT metadata FROM checkpoints
    ORDER BY rowid DESC LIMIT 200
""")
from collections import Counter
modes = Counter()
plan_modes = Counter()
for (meta_blob,) in cur.fetchall():
    if not meta_blob:
        continue
    try:
        meta = json.loads(meta_blob)
        modes[meta.get('mode')] += 1
        plan_modes[meta.get('is_plan_mode')] += 1
    except Exception:
        pass
print('mode distribution (last 200 checkpoints):', dict(modes))
print('is_plan_mode distribution:', dict(plan_modes))

# Check if TodoMiddleware was EVER in the middleware chain - check for write_todos in any checkpoint's tools
cur.execute("SELECT COUNT(*) FROM checkpoints WHERE checkpoint LIKE '%write_todos%'")
print('\ncheckpoints containing write_todos tool:', cur.fetchone()[0])