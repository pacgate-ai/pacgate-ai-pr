$ErrorActionPreference = "Continue"
$root = "c:\Users\pacga\github-pr\pacgate-law"
Set-Location $root
function Section($t) { Write-Output ""; Write-Output "===== $t =====" }

Section "Does the IMAGE bake skills? (run without the mount)"
docker run --rm --entrypoint sh ghcr.io/jzkk720/deer-flow-pacgate:0.1.31 -c "echo 'baked /app/skills/public:'; ls /app/skills/public 2>/dev/null | wc -l; echo 'baked /app/skills:'; ls /app/skills 2>/dev/null | head" 2>$null

Section "PERSONAS: DB table or files?"
docker exec pacgate-db psql -U pacgate -d pacgate -c "\dt" 2>$null | Select-String -Pattern "persona|soul|agent|workflow"
Write-Output "--- personas table ---"
docker exec pacgate-db psql -U pacgate -d pacgate -c "\d personas" 2>$null
Write-Output "--- persona count ---"
docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select count(*) from personas;" 2>$null

Section "WORKFLOWS: DB table or files?"
docker exec pacgate-db psql -U pacgate -d pacgate -c "\d workflows" 2>$null
Write-Output "--- workflow count ---"
docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select count(*) from workflows;" 2>$null

Section "How do the 15 YAML files relate to the 222 workflows?"
Write-Output "--- sample of workflow names in DB ---"
docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select name from workflows order by name limit 15;" 2>$null
Write-Output "--- distinct categories ---"
docker exec pacgate-db psql -U pacgate -d pacgate -t -c "select count(distinct category) from workflows;" 2>$null

Section "Is there a SEED mechanism for workflows/personas?"
Get-ChildItem -Path "pacgate-ai" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match "seed" -and $_.FullName -notmatch "\\data\\|node_modules|\\target\\" } |
  Select-Object -First 20 | ForEach-Object { Write-Output ("  " + $_.FullName.Replace($root,"")) }

Section "Migrations — do they seed workflows/personas?"
Get-ChildItem -Path "pacgate-ai" -Recurse -Filter "*.sql" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "migration" } |
  ForEach-Object { Write-Output ("  " + $_.Name + "  (" + $_.Length + "b)") }
