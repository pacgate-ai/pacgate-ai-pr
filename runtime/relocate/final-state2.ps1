$r = 'c:\Users\pacga\github-pr\pacgate-law'
"=== 1. COMMITS ==="
& git -C $r rev-list --count HEAD
"=== 2. CONTAINERS ==="
$c = docker ps -q
"running: $(@($c).Count)"
"=== 3. MOUNTS UNDER OLD PATH ==="
$old = (docker ps -q | ForEach-Object { docker inspect --format '{{.Name}}|{{range .Mounts}}{{.Source}};{{end}}' $_ }) |
       Select-String ([char]0x43 + ':\\pacgate-ai-pr')
if ($old) { "FOUND: $(@($old).Count)"; $old } else { "0 mounts under old path - CLEAN" }
"=== 4. MOUNTS UNDER NEW PATH ==="
$new = (docker ps -q | ForEach-Object { docker inspect --format '{{.Name}}|{{range .Mounts}}{{.Source}};{{end}}' $_ }) |
       Select-String 'pacgate-law'
"count: $(@($new).Count)"
"=== 5. IMAGES (local-verify) ==="
docker images --format '{{.Repository}}:{{.Tag}}|{{.Size}}|{{.CreatedSince}}' | Select-String 'local-verify'
"=== 6. ARCHIVE ==="
Get-ChildItem 'C:\archive-pacgate-ai-pr' -ErrorAction SilentlyContinue |
   ForEach-Object { "$($_.Name)  $([math]::Round($_.Length/1MB,1)) MB" }
"=== 7. OLD LOCATION STATUS ==="
"exists: $(Test-Path 'C:\pacgate-ai-pr')  (kept as rollback)"
"=== 8. DISK ==="
$d = Get-PSDrive C
"free: $([math]::Round($d.Free/1GB,1)) GB"