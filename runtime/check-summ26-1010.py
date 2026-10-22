import sys
sys.path.insert(0, '/app/backend')

# The branch DID execute (versions_seen advanced). The middleware ran and
# returned None. But our direct invocation with the SAME messages returned
# 20 messages. The difference must be the MESSAGES the middleware saw.
# During the live run, the state passed to before_model may include messages
# that our checkpoint reconstruction lacks (e.g. the middleware sees the state
# BEFORE the model call at that step, which may differ).
# DECISIVE: instrument the live middleware. Patch the container file to log
# the decision, restart, run a real request, read logs. (Known playbook.)
# First check if the file is bind-mounted or baked in
import subprocess
out = subprocess.run(['grep', '-c', 'def _amaybe_summarize', '/app/backend/packages/harness/deerflow/agents/middlewares/summarization_middleware.py'], capture_output=True, text=True)
print('file present:', out.stdout.strip())
# Check mount status
out2 = subprocess.run(['sh', '-c', 'mount | grep summar || echo "not a separate mount"'], capture_output=True, text=True)
print(out2.stdout)
# Check if the file differs from the image layer (i.e. patched at runtime)
out3 = subprocess.run(['sh', '-c', 'ls -la /app/backend/packages/harness/deerflow/agents/middlewares/summarization_middleware.py'], capture_output=True, text=True)
print(out3.stdout)