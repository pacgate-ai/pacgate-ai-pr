import sqlite3, json

for db in ("/app/backend/.deer-flow/data/deer-flow.db", "/app/backend/.deer-flow/data/deerflow.db"):
    try:
        conn = sqlite3.connect(db)
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [r[0] for r in cur.fetchall()]
        print(f"== {db}: {tables}")
        for t in tables:
            if "run" in t.lower():
                cur.execute(f"PRAGMA table_info({t})")
                cols = [r[1] for r in cur.fetchall()]
                print(f"  {t} cols: {cols}")
                if "run_id" in cols or "id" in cols:
                    idcol = "run_id" if "run_id" in cols else "id"
                    try:
                        cur.execute(f"SELECT * FROM {t} WHERE {idcol} LIKE 'ef4969ba%' OR {idcol} LIKE '2697fce5%'")
                        for row in cur.fetchall():
                            print(f"  ROW: {row}")
                    except Exception as e:
                        print(f"  query failed: {e}")
        conn.close()
    except Exception as e:
        print(f"== {db}: FAILED {e}")
