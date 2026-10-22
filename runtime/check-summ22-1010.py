import sys
sys.path.insert(0, '/app/backend')

# cutoff>0 from checkpoint 8 onward (5428 tokens, 8 messages). So summarization
# SHOULD have fired from step ~8 through step 94. It didn't. The middleware
# writes were empty. WHY?
# Hypothesis: the middleware's before_model node is NOT in the executed graph
# path. The writes showed 'branch:to:DeerFlowSummarizationMiddleware.before_model'
# - a BRANCH channel, not the middleware's own output channel. Check whether
# the branch actually executed by looking at versions_seen.
# Simpler: check if the summary model call EVER hit Ollama during the run.
# The Ollama log would show /api/chat calls from the summarizer.
# Actually - the deer-flow logs showed NO summarization log lines at all.
# Check if the middleware logs when it fires
import subprocess
out = subprocess.run(['grep', '-n', 'logger\\|logging\\|log\\.', '/app/backend/packages/harness/deerflow/agents/middlewares/summarization_middleware.py'], capture_output=True, text=True)
print(out.stdout[:2000])