# Verify the configured memory storage class is importable BEFORE applying the
# stricter memory-storage patch. The patch raises when a configured class cannot
# be built, so an unimportable adapter would turn a silent degradation into a
# hard startup failure. Better to find that out here than after a recreate.

$py = @'
import sys
sys.path.insert(0, "/app/backend")
try:
    from pacgate_deerflow_adapter.storage import PacgateMemoryStorage
    print("IMPORT OK:", PacgateMemoryStorage)
except Exception as e:
    print("IMPORT FAILED:", type(e).__name__, e)
    sys.exit(1)

# Also prove the class can actually be INSTANTIATED with the live config, which
# is the exact operation the patch guards.
try:
    from deerflow.config import get_app_config
    cfg = get_app_config()
    mc = cfg.memory
    print("configured storage_class:", mc.storage_class)
    print("configured model_name   :", mc.model_name)
except Exception as e:
    print("CONFIG READ FAILED:", type(e).__name__, e)
    sys.exit(1)
'@

$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($py))
docker exec deer-flow sh -c "echo $b64 | base64 -d > /tmp/check_mem.py"
docker exec deer-flow sh -c "cd /app/backend && .venv/bin/python /tmp/check_mem.py"
exit $LASTEXITCODE
