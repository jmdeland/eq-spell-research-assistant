param()
$ErrorActionPreference='Continue'
$root=$PSScriptRoot
$configPath=Join-Path $root 'monitor-config.json'
function Result([string]$Label,[bool]$Ok,[string]$Detail=''){
 if($Ok){ Write-Host ('  [OK]   ' + $Label) -ForegroundColor Green } else { Write-Host ('  [FIX]  ' + $Label) -ForegroundColor Yellow }
 if($Detail){Write-Host ('         ' + $Detail) -ForegroundColor DarkGray}
}
Clear-Host
Write-Host ''
Write-Host 'EverQuest Research & Loot Tool - Setup Check' -ForegroundColor Cyan
Write-Host '------------------------------------------------------------'
Write-Host ''
$required=@('live-monitor.ps1','live-event-worker.ps1','persistence-worker.ps1','history-index-worker.ps1','research-tool-tray.ps1','index.html','app.js')
$missing=@($required | Where-Object {-not(Test-Path -LiteralPath (Join-Path $root $_))})
Result 'Application files' ($missing.Count -eq 0) $(if($missing.Count){'Missing: '+($missing -join ', ')}else{'Core files are present.'})
$config=$null
try{ if(Test-Path -LiteralPath $configPath){$config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json} }catch{}
$logPath=$(if($config){[string]$config.logPath}else{''})
$logOk=($logPath -and (Test-Path -LiteralPath $logPath))
Result 'EverQuest log' $logOk $(if($logOk){$logPath}else{'No usable log is saved yet. The app will help you choose one when it starts.'})
if($logOk){ try{$fi=Get-Item -LiteralPath $logPath;Result 'Log activity' (((Get-Date)-$fi.LastWriteTime).TotalHours -le 24) ('Last updated: '+$fi.LastWriteTime)}catch{} }
$online=$false;$status=$null
try{$status=Invoke-RestMethod 'http://127.0.0.1:8765/api/status' -TimeoutSec 2;$online=($status -and $status.active -eq $true)}catch{}
Result 'Main app service' $online $(if($online){'Version '+$status.version+', Character '+$status.character}else{'Not currently running. This is normal if the app is closed.'})
if($online){
 $live=$false;try{$p=Invoke-RestMethod 'http://127.0.0.1:8767/api/live-poll?after=0' -TimeoutSec 2;$live=($null -ne $p)}catch{};Result 'Live Loot worker' $live $(if($live){'Live worker responded.'}else{'Live worker did not respond.'})
 $persist=$false;try{$p=Invoke-RestMethod 'http://127.0.0.1:8766/api/persistence-health' -TimeoutSec 2;$persist=($p.ok -eq $true)}catch{};Result 'Persistence worker' $persist $(if($persist){'Session/history persistence responded.'}else{'Persistence worker did not respond.'})
}
Write-Host ''
Read-Host 'Press Enter to return to Easy Start'
