"""Per-model token split for recent runs — who actually does the work?"""
import json
import sqlite3

c = sqlite3.connect("file:/app/backend/.deer-flow/data/deerflow.db?mode=ro", uri=True)
rows = c.execute(
    "SELECT created_at, thread_id, model_name, total_input_tokens, total_output_tokens, "
    "token_usage_by_model, llm_call_count, middleware_tokens, lead_agent_tokens FROM runs "
    "ORDER BY created_at DESC LIMIT 12"
).fetchall()
for created, tid, mn, ti, to, bym, calls, mw, lead in rows:
    print(f"\n--- {created} thread={str(tid)[:12]} run_model={mn}")
    print(f"    total_in={ti} total_out={to} calls={calls} middleware_tok={mw} lead_tok={lead}")
    if bym:
        try:
            d = json.loads(bym)
            for model, v in sorted(d.items(), key=lambda kv: -(kv[1].get("input_tokens", 0) if isinstance(kv[1], dict) else 0)):
                if isinstance(v, dict):
                    print(f"      {model:34} in={v.get('input_tokens')} out={v.get('output_tokens')} calls={v.get('api_calls') or v.get('call_count') or ''}")
                else:
                    print(f"      {model:34} {v}")
        except Exception as e:  # noqa: BLE001
            print("      parse fail:", e, str(bym)[:200])
c.close()
