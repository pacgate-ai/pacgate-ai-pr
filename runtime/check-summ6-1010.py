import sqlite3
conn = sqlite3.connect('/app/backend/.deer-flow/checkpoints.db')
cur = conn.cursor()
tid = '630881f0-0c23-4ef9-ada7-e860c8033045'
# 64% CJK. The summarization trigger=5000 message tokens. The middleware's token
# estimate for CJK text: len(text)//4 chars-per-token heuristic UNDERCOUNTS CJK
# (CJK is ~1-1.5 chars/token, not 4). So 40k chars of CJK counts as ~10k tokens
# by the heuristic but is really ~30k+.
# BUT WAIT - the trigger is 5000 and even the undercounted estimate would exceed it.
# Let me check the middleware's ACTUAL trigger evaluation. Read the source.
import subprocess
out = subprocess.run(['grep', '-n', 'def.*trigger\|_should_summarize\|count_tokens', '/app/backend/packages/harness/deerflow/agents/middlewares/summarization_middleware.py'], capture_output=True, text=True)
print(out.stdout)
out2 = subprocess.run(['ls', '/app/backend/packages/harness/deerflow/agents/middlewares/'], capture_output=True, text=True)
print(out2.stdout)