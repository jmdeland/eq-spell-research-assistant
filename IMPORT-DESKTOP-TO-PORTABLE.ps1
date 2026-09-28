param()
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$desktop=Join-Path $env:LOCALAPPDATA 'EverQuest Research & Loot Tool'
$portable=Join-Path $root 'portable-data'
$desktopHistory=Join-Path $desktop 'history'
$portableHistory=Join-Path $portable 'history'

function Read-Lines([string]$p){ if(Test-Path -LiteralPath $p){ return @(Get-Content -LiteralPath $p | Where-Object{-not [string]::IsNullOrWhiteSpace($_)})}; return @() }
function Key([string]$line){ try{$o=$line|ConvertFrom-Json;if($o.historyId){return 'id:'+[string]$o.historyId}}catch{};return 'raw:'+$line }
function Write-Lines([string]$p,[string[]]$lines){$d=Split-Path -Parent $p;if(-not(Test-Path $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null};$enc=New-Object System.Text.UTF8Encoding($false);[IO.File]::WriteAllLines($p,$lines,$enc)}

if(-not(Test-Path -LiteralPath $desktop)){ exit 0 }
if(-not(Test-Path -LiteralPath $portable)){New-Item -ItemType Directory -Path $portable -Force|Out-Null}

$existing=@(Get-ChildItem -LiteralPath $portable -Force -ErrorAction SilentlyContinue)
$backup=$null
if($existing.Count -gt 0){
  $backup=Join-Path $root ('portable-data_backup_'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Path $backup -Force|Out-Null
  foreach($i in $existing){Copy-Item -LiteralPath $i.FullName -Destination $backup -Recurse -Force}
  Write-Host ('Portable backup created: '+$backup) -ForegroundColor Green
}

Write-Host 'Merging Desktop Observed Loot History into Portable Mode...' -ForegroundColor Cyan
$names=@()
if(Test-Path $desktopHistory){$names+=@(Get-ChildItem $desktopHistory -Filter 'loot-history-????-??.jsonl' -File -ErrorAction SilentlyContinue|% Name)}
if(Test-Path $portableHistory){$names+=@(Get-ChildItem $portableHistory -Filter 'loot-history-????-??.jsonl' -File -ErrorAction SilentlyContinue|% Name)}
$names=@($names|Sort-Object -Unique)
$dCount=0;$pCount=0;$dupes=0;$mergedCount=0
foreach($n in $names){
 $dl=Read-Lines (Join-Path $desktopHistory $n);$pl=Read-Lines (Join-Path $portableHistory $n);$dCount+=$dl.Count;$pCount+=$pl.Count
 $seen=New-Object 'System.Collections.Generic.HashSet[string]';$out=New-Object 'System.Collections.Generic.List[string]'
 foreach($line in @($pl)+@($dl)){ $k=Key $line;if($seen.Add($k)){[void]$out.Add($line)}else{$dupes++} }
 Write-Lines (Join-Path $portableHistory $n) @($out);$mergedCount+=$out.Count
}
Remove-Item (Join-Path $portableHistory 'loot-history-index.json') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $portableHistory 'history-index-worker-state.json') -Force -ErrorAction SilentlyContinue

$skip=@('tray.pid','install-root.txt','update-shutdown-request.json','suppress-browser-once.flag','loot-history-index.json','history-index-worker-state.json')
$files=@(Get-ChildItem $desktop -Recurse -File -Force -ErrorAction SilentlyContinue|?{$skip -notcontains $_.Name -and $_.Name -notlike 'loot-history-????-??.jsonl'})
$copied=0
foreach($f in $files){$rel=$f.FullName.Substring($desktop.Length).TrimStart('\\');$dst=Join-Path $portable $rel;$dd=Split-Path -Parent $dst;if(-not(Test-Path $dd)){New-Item -ItemType Directory -Path $dd -Force|Out-Null};Copy-Item $f.FullName $dst -Force;$copied++}
Write-Host ('Desktop history records: '+$dCount)
Write-Host ('Existing portable records: '+$pCount)
Write-Host ('Duplicates skipped: '+$dupes)
Write-Host ('Merged portable history: '+$mergedCount) -ForegroundColor Green
Write-Host ('Other Desktop data files copied: '+$copied) -ForegroundColor Green
@{importedAt=(Get-Date).ToString('o');source=$desktop;backup=$backup}|ConvertTo-Json|Set-Content (Join-Path $portable 'desktop-import-complete.json') -Encoding UTF8
