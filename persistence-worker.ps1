param(
    [Parameter(Mandatory=$true)][int]$ParentPid
)

$ErrorActionPreference="Stop"
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath=Join-Path $root "monitor-config.json"
$userDataRoot=Join-Path $env:LOCALAPPDATA "EverQuest Research & Loot Tool"
if(-not(Test-Path -LiteralPath $userDataRoot)){New-Item -ItemType Directory -Path $userDataRoot -Force|Out-Null}
$sessionStatePath=Join-Path $userDataRoot "session-loot.jsonl"
$sessionMetaPath=Join-Path $userDataRoot "session-meta.json"
$historyRoot=Join-Path $userDataRoot "history"
if(-not(Test-Path -LiteralPath $historyRoot)){New-Item -ItemType Directory -Path $historyRoot -Force|Out-Null}

function Read-JsonRequest($req){
    $reader=New-Object IO.StreamReader($req.InputStream,$req.ContentEncoding)
    try{$raw=$reader.ReadToEnd()}finally{$reader.Dispose()}
    if(-not $raw){return $null}
    return ($raw|ConvertFrom-Json)
}
function Get-CurrentSessionId {
    if(Test-Path -LiteralPath $sessionMetaPath){
        try{
            $m=Get-Content -LiteralPath $sessionMetaPath -Raw|ConvertFrom-Json
            if($m.sessionId){return [string]$m.sessionId}
        }catch{}
    }
    return ""
}
function History-Enabled {
    if(Test-Path -LiteralPath $configPath){
        try{
            $c=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
            return ($c.observedLootHistoryEnabled -ne $false)
        }catch{}
    }
    return $true
}
function Get-HistoryMonthKey($evt){
    $dt=$null
    foreach($candidate in @($evt.recordedAt,$evt.historyRecordedAt,$evt.timestamp)){
        if($candidate){try{$dt=[DateTime]::Parse([string]$candidate);break}catch{}}
    }
    if(-not $dt){$dt=Get-Date}
    return $dt.ToString("yyyy-MM")
}
function Append-History($items){
    if(-not(History-Enabled)){return 0}
    $byMonth=@{};$written=0
    foreach($evt in @($items)){
        if($null -eq $evt){continue}
        if(($evt.PSObject.Properties["excludeFromObservedHistory"] -and $evt.excludeFromObservedHistory) -or ($evt.PSObject.Properties["corpseRecovery"] -and $evt.corpseRecovery)){continue}
        if(-not $evt.historyId){$evt|Add-Member -NotePropertyName historyId -NotePropertyValue ([guid]::NewGuid().ToString("N")) -Force}
        if(-not $evt.historyRecordedAt){$evt|Add-Member -NotePropertyName historyRecordedAt -NotePropertyValue ((Get-Date).ToString("o")) -Force}
        $month=Get-HistoryMonthKey $evt
        if(-not $byMonth.ContainsKey($month)){$byMonth[$month]=New-Object System.Collections.Generic.List[string]}
        $byMonth[$month].Add(($evt|ConvertTo-Json -Depth 10 -Compress))
    }
    foreach($month in $byMonth.Keys){
        $path=Join-Path $historyRoot ("loot-history-"+$month+".jsonl")
        $lines=$byMonth[$month].ToArray()
        if($lines.Count -gt 0){Add-Content -LiteralPath $path -Value $lines -Encoding UTF8;$written+=$lines.Count}
    }
    return $written
}
function Append-SessionEvents($items,[string]$submittedSessionId){
    $batch=@($items)
    $current=Get-CurrentSessionId
    if(-not $submittedSessionId -or -not $current -or $submittedSessionId -ne $current){
        return [pscustomobject]@{ok=$false;staleSession=$true;rejectedCount=$batch.Count;submittedSessionId=$submittedSessionId;currentSessionId=$current}
    }
    if($batch.Count -eq 0){return [pscustomobject]@{ok=$true;count=0;historyCount=0;sessionId=$current}}
    $lines=New-Object System.Collections.Generic.List[string]
    foreach($evt in $batch){
        if($null -eq $evt){continue}
        $evt|Add-Member -NotePropertyName sessionId -NotePropertyValue $current -Force
        $lines.Add(($evt|ConvertTo-Json -Depth 8 -Compress))
    }
    if($lines.Count -gt 0){Add-Content -LiteralPath $sessionStatePath -Value $lines.ToArray() -Encoding UTF8}
    $hc=Append-History $batch
    return [pscustomobject]@{ok=$true;count=$lines.Count;historyCount=$hc;sessionId=$current}
}
function Write-Response($res,$obj,[int]$status=200){
    $payload=$obj|ConvertTo-Json -Depth 8
    $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
    $res.StatusCode=$status
    $res.ContentType="application/json; charset=utf-8"
    $res.Headers["Access-Control-Allow-Origin"]="*"
    $res.Headers["Access-Control-Allow-Methods"]="GET, POST, OPTIONS"
    $res.Headers["Access-Control-Allow-Headers"]="Content-Type"
    $res.ContentLength64=$bytes.Length
    $res.OutputStream.Write($bytes,0,$bytes.Length)
}

$listener=New-Object Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:8766/")
$listener.Start()

try{
    while($listener.IsListening){
        if(-not(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){break}
        $task=$listener.GetContextAsync()
        while(-not $task.Wait(250)){
            if(-not(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){break}
        }
        if(-not $task.IsCompleted){continue}
        $ctx=$task.Result;$req=$ctx.Request;$res=$ctx.Response
        try{
            if($req.HttpMethod -eq "OPTIONS"){$res.StatusCode=204;continue}
            $path=$req.Url.AbsolutePath
            if($path -eq "/api/session-events"){
                $body=Read-JsonRequest $req
                $items=@();if($body -and $body.events){$items=@($body.events)}
                $result=Append-SessionEvents $items ([string]$body.sessionId)
                Write-Response $res $result $(if($result.staleSession){409}else{200})
                continue
            }
            if($path -eq "/api/persistence-health"){
                Write-Response $res ([pscustomobject]@{ok=$true;sessionId=(Get-CurrentSessionId);historyEnabled=(History-Enabled)})
                continue
            }
            Write-Response $res ([pscustomobject]@{ok=$false;error="Not found"}) 404
        }catch{
            try{Write-Response $res ([pscustomobject]@{ok=$false;error=$_.Exception.Message}) 500}catch{}
        }finally{
            try{$res.OutputStream.Close()}catch{}
        }
    }
}finally{
    try{$listener.Stop()}catch{}
    try{$listener.Close()}catch{}
}
