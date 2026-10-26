# Prove the memory-storage patch does what it claims, in BOTH directions.
#
# The defect it fixes: get_memory_storage() wrapped instantiation in a bare
# `except Exception` and substituted FileMemoryStorage, logging at error level
# only. FileMemoryStorage writes plaintext JSON to the local filesystem - outside
# the pacgate-api sanitization gate, outside the audit log, invisible to every
# health check. A compliance failure wearing a healthy face.
#
# IMPORTANT: the patch treats "storage_class == the default FileMemoryStorage"
# as "nothing was configured" and still falls back (with an INFO log). That is
# deliberate - a fresh install with no config must keep working. So a probe that
# calls get_memory_storage() WITHOUT first calling get_app_config() reads the
# module-level default and legitimately gets FileMemoryStorage. That is the
# initialization-order bug the commit describes, not a live degradation.
#
# This probe therefore tests the REAL runtime order:
#   A. after get_app_config(), the configured class must be PacgateMemoryStorage
#   B. a CONFIGURED class that cannot be built must RAISE (not degrade)
#   C. the real configured class must still build

$py = @'
import sys
sys.path.insert(0, "/app/backend")

from deerflow.config import get_app_config
from deerflow.config.memory_config import get_memory_config
from deerflow.agents.memory import storage as S

rc = 0

# --- A. real runtime order: config first, then storage ----------------------
cfg = get_app_config()
mc = get_memory_config()
print("A: configured storage_class =", mc.storage_class)

if mc.storage_class == "deerflow.agents.memory.storage.FileMemoryStorage":
    print("FAIL A: config resolves to the DEFAULT FileMemoryStorage - memory is off the gate")
    rc = 1
else:
    print("PASS A: a non-default storage class is configured")

# --- B. a configured class that cannot be built must RAISE ------------------
original = mc.storage_class
try:
    mc.storage_class = "__main__._Boom"
    # Reset the singleton so the guard actually runs.
    S._storage_instance = None
    try:
        S.get_memory_storage()
        print("FAIL B: a broken configured class did NOT raise - the patch is not active")
        rc = 1
    except Exception as e:
        print("PASS B: broken configured class raised %s: %s" % (type(e).__name__, str(e)[:100]))
finally:
    mc.storage_class = original
    S._storage_instance = None

# --- C. the real configured class must still build --------------------------
try:
    st = S.get_memory_storage()
    name = type(st).__name__
    if name == "FileMemoryStorage":
        print("FAIL C: fell back to FileMemoryStorage - memory is OFF the sanitization gate")
        rc = 1
    else:
        print("PASS C: real configured class built -> %s" % name)
except Exception as e:
    print("FAIL C: real configured class failed to build: %s: %s" % (type(e).__name__, e))
    rc = 1

print("RESULT:", "PASS" if rc == 0 else "FAIL")
sys.exit(rc)
'@

$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($py))
docker exec deer-flow sh -c "echo $b64 | base64 -d > /tmp/probe_mem2.py"
docker exec deer-flow sh -c "cd /app/backend && .venv/bin/python /tmp/probe_mem2.py 2>&1 | grep -v LangChainPendingDeprecationWarning | grep -v 'from langgraph'"
exit $LASTEXITCODE
