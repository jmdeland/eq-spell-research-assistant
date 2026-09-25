param(
    [Parameter(Mandatory=$true)][int]$ParentPid
)

$ErrorActionPreference="SilentlyContinue"
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath=Join-Path $root "monitor-config.json"
$appVersionPath=Join-Path $root "app-version.json"
$userDataRoot=Join-Path $env:LOCALAPPDATA "EverQuest Research & Loot Tool"
$sessionMetaPath=Join-Path $userDataRoot "session-meta.json"

function Read-Config {
    if(Test-Path -LiteralPath $configPath){
        try{return (Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json)}catch{}
    }
    return [pscustomobject]@{logPath="";observedLootHistoryEnabled=$true}
}
function Read-AppVersion {
    if(Test-Path -LiteralPath $appVersionPath){
        try{return (Get-Content -LiteralPath $appVersionPath -Raw|ConvertFrom-Json)}catch{}
    }
    return [pscustomobject]@{version="unknown";channel="demo"}
}
function Read-SessionId {
    if(Test-Path -LiteralPath $sessionMetaPath){
        try{
            $m=Get-Content -LiteralPath $sessionMetaPath -Raw|ConvertFrom-Json
            if($m.sessionId){return [string]$m.sessionId}
        }catch{}
    }
    return ""
}

$config=Read-Config
$logPath=[string]$config.logPath
$logFileName=""
$character=""
if($logPath){
    try{$logFileName=[IO.Path]::GetFileName($logPath)}catch{}
    if($logFileName -match '^eqlog_(.+?)_[^_]+\.txt$'){$character=$Matches[1]}
}

$events=New-Object System.Collections.ArrayList
$nextId=1
$position=0L
$carry=""
$currentSessionId=Read-SessionId
$currentZone=""
$currentZoneId=$null
$currentInstanceId=$null
$currentZoneVersion=$null
$currentZoneEnteredAt=$null
$lastZoneEntryLogTime=$null
$currentZoneIsGenericInstance=$false
$corpseRecoveryPending=$false
$corpseRecoveryActive=$false
$corpseRecoveryActivatedAt=$null
$corpseRecoveryLastLootAt=$null
$corpseRecoveryFirstLootSeen=$false
$corpseRecoveryStartWindowSeconds=120
$corpseRecoveryIdleWindowSeconds=60
$corpseRecoveryMaxWindowSeconds=600

function Reset-CorpseRecoveryContext {
    $script:corpseRecoveryPending=$false
    $script:corpseRecoveryActive=$false
    $script:corpseRecoveryActivatedAt=$null
    $script:corpseRecoveryLastLootAt=$null
    $script:corpseRecoveryFirstLootSeen=$false
}
function Update-CorpseRecoveryContextFromLine([string]$line){
    if(-not $line){return}
    $res=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*You regain experience from resurrection\.')
    if($res.Success){
        $script:corpseRecoveryPending=$true
        $script:corpseRecoveryActive=$false
        $script:corpseRecoveryActivatedAt=$null
        $script:corpseRecoveryLastLootAt=$null
        $script:corpseRecoveryFirstLootSeen=$false
        return
    }
    $zone=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*You have entered (?<zone>.+?)\.\s*$')
    if($zone.Success){
        $t=Parse-EqLogTime $zone.Groups['time'].Value
        if($script:corpseRecoveryPending){
            $script:corpseRecoveryPending=$false
            $script:corpseRecoveryActive=$true
            $script:corpseRecoveryActivatedAt=$(if($t){$t}else{Get-Date})
            $script:corpseRecoveryLastLootAt=$null
            $script:corpseRecoveryFirstLootSeen=$false
            return
        }
        if($script:corpseRecoveryActive){Reset-CorpseRecoveryContext}
    }
}
function Get-CorpseRecoveryLootState([string]$timestamp){
    if(-not $script:corpseRecoveryActive){return $false}
    $t=Parse-EqLogTime $timestamp
    if(-not $t){$t=Get-Date}
    if($script:corpseRecoveryActivatedAt){
        $age=($t-$script:corpseRecoveryActivatedAt).TotalSeconds
        if($age -gt $script:corpseRecoveryMaxWindowSeconds){Reset-CorpseRecoveryContext;return $false}
        if(-not $script:corpseRecoveryFirstLootSeen -and $age -gt $script:corpseRecoveryStartWindowSeconds){Reset-CorpseRecoveryContext;return $false}
    }
    if($script:corpseRecoveryFirstLootSeen -and $script:corpseRecoveryLastLootAt){
        $idle=($t-$script:corpseRecoveryLastLootAt).TotalSeconds
        if($idle -gt $script:corpseRecoveryIdleWindowSeconds){Reset-CorpseRecoveryContext;return $false}
    }
    $script:corpseRecoveryFirstLootSeen=$true
    $script:corpseRecoveryLastLootAt=$t
    return $true
}

function Test-GenericInstanceZoneName([string]$zone){
    if([string]::IsNullOrWhiteSpace($zone)){return $false}
    $z=$zone.Trim()
    return [regex]::IsMatch($z,'^(?:a|an)?\s*instanced\s+version\s+of\s+(?:the\s+)?zone$','IgnoreCase')
}
function Parse-EqLogTime([string]$value){
    if([string]::IsNullOrWhiteSpace($value)){return $null}
    try{return [DateTime]::Parse($value,[Globalization.CultureInfo]::InvariantCulture)}catch{}
    try{return [DateTime]::Parse($value)}catch{}
    return $null
}
function Update-ZoneContextFromLine([string]$line){
    if(-not $line){return}
    $m=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*You have entered (?<zone>.+?)\.\s*$')
    if($m.Success){
        $zone=$m.Groups['zone'].Value.Trim()
        $script:currentZone=$zone
        $script:currentZoneId=$null
        $script:currentInstanceId=$null
        $script:currentZoneVersion=$null
        $script:currentZoneEnteredAt=$m.Groups['time'].Value
        $script:lastZoneEntryLogTime=Parse-EqLogTime $m.Groups['time'].Value
        $script:currentZoneIsGenericInstance=Test-GenericInstanceZoneName $zone
        return
    }
    $m=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*PID \(\d+\)\s+(?<zone>.+?)\s+\((?<zoneId>\d+)\)\s+\(Instance ID (?<instanceId>\d+)\)\s+\(Version (?<version>\d+)\)')
    if($m.Success){
        $zone=$m.Groups['zone'].Value.Trim()
        $pidTime=Parse-EqLogTime $m.Groups['time'].Value
        $nearZoneTransition=$false
        if($pidTime -and $script:lastZoneEntryLogTime){
            try{$nearZoneTransition=([Math]::Abs(($pidTime-$script:lastZoneEntryLogTime).TotalSeconds) -le 30)}catch{}
        }
        $sameZone=([string]::Equals([string]$script:currentZone,$zone,[StringComparison]::OrdinalIgnoreCase))
        if(-not $script:currentZone -or $script:currentZoneIsGenericInstance -or $sameZone -or $nearZoneTransition){
            # Bastion's PID line is the authoritative identity for the instance.
            # It replaces generic client text such as "a Instanced Version of the zone".
            $script:currentZone=$zone
            $script:currentZoneId=[int]$m.Groups['zoneId'].Value
            $script:currentInstanceId=[int]$m.Groups['instanceId'].Value
            $script:currentZoneVersion=[int]$m.Groups['version'].Value
            $script:currentZoneIsGenericInstance=$false
        }
    }
}
function Initialize-ZoneFromTail {
    if(-not $logPath -or -not(Test-Path -LiteralPath $logPath)){return}
    try{
        $fi=Get-Item -LiteralPath $logPath
        $tailBytes=[Math]::Min([int64](16MB),[int64]$fi.Length)
        if($tailBytes -le 0){return}
        $fs=New-Object IO.FileStream($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try{
            [void]$fs.Seek(-$tailBytes,[IO.SeekOrigin]::End)
            $sr=New-Object IO.StreamReader($fs)
            try{$text=$sr.ReadToEnd()}finally{$sr.Dispose()}
        }finally{$fs.Dispose()}
        foreach($line in ($text -split "`r?`n")){Update-CorpseRecoveryContextFromLine $line;Update-ZoneContextFromLine $line}
    }catch{}
}
function Parse-LootLine([string]$line){
    if(-not $line){return $null}
    $m=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*--You have looted (?:a|an) (?<item>.+?)\.--\s*$')
    if($m.Success){
        return [pscustomobject]@{
            timestamp=$m.Groups['time'].Value
            looter=$(if($character){$character}else{"You"})
            self=$true
            item=$m.Groups['item'].Value
            zone=$script:currentZone
            zoneId=$script:currentZoneId
            instanceId=$script:currentInstanceId
            zoneVersion=$script:currentZoneVersion
        }
    }
    $m=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*--(?<looter>.+?) has looted (?:a|an) (?<item>.+?)\.--\s*$')
    if($m.Success){
        $l=$m.Groups['looter'].Value
        return [pscustomobject]@{
            timestamp=$m.Groups['time'].Value
            looter=$l
            self=$(if($character -and $l -eq $character){$true}else{$false})
            item=$m.Groups['item'].Value
            zone=$script:currentZone
            zoneId=$script:currentZoneId
            instanceId=$script:currentInstanceId
            zoneVersion=$script:currentZoneVersion
        }
    }
    return $null
}
function Reset-ToCurrentEnd {
    try{
        $fi=Get-Item -LiteralPath $logPath -ErrorAction Stop
        $script:position=[int64]$fi.Length
    }catch{$script:position=0L}
    $script:carry=""
    $events.Clear()
}
function Check-SessionRotation {
    $sid=Read-SessionId
    if($sid -and $sid -ne $script:currentSessionId){
        $script:currentSessionId=$sid
        Reset-ToCurrentEnd
    }
}
function Read-NewLoot {
    if(-not $logPath -or -not(Test-Path -LiteralPath $logPath)){return}
    Check-SessionRotation
    $fi=Get-Item -LiteralPath $logPath
    if($fi.Length -lt $script:position){
        $script:position=0L
        $script:carry=""
    }
    if($fi.Length -eq $script:position){return}

    $fs=New-Object IO.FileStream($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        [void]$fs.Seek($script:position,[IO.SeekOrigin]::Begin)
        $sr=New-Object IO.StreamReader($fs)
        try{
            $chunk=$sr.ReadToEnd()
            $script:position=[int64]$fs.Position
        }finally{$sr.Dispose()}
    }finally{$fs.Dispose()}

    if(-not $chunk){return}
    $chunk=$script:carry+$chunk
    $parts=$chunk -split "`r?`n",-1
    if($chunk -notmatch "(`r`n|`n)$"){
        $script:carry=$parts[-1]
        if($parts.Count -gt 1){$parts=$parts[0..($parts.Count-2)]}else{$parts=@()}
    }else{$script:carry=""}

    foreach($line in $parts){
        Update-CorpseRecoveryContextFromLine $line
        Update-ZoneContextFromLine $line
        $evt=Parse-LootLine $line
        if($evt){
            $isCorpseRecovery=$false
            if($evt.self){$isCorpseRecovery=Get-CorpseRecoveryLootState ([string]$evt.timestamp)}
            $evt|Add-Member -NotePropertyName corpseRecovery -NotePropertyValue $isCorpseRecovery -Force
            $evt|Add-Member -NotePropertyName lootSource -NotePropertyValue $(if($isCorpseRecovery){"corpse_recovery"}else{"observed"}) -Force
            $evt|Add-Member -NotePropertyName excludeFromObservedHistory -NotePropertyValue $isCorpseRecovery -Force
            $evt|Add-Member -NotePropertyName id -NotePropertyValue $nextId -Force
            $evt|Add-Member -NotePropertyName detectedAt -NotePropertyValue ((Get-Date).ToString("o")) -Force
            [void]$events.Add($evt)
            $script:nextId++
        }
    }
    while($events.Count -gt 1000){$events.RemoveAt(0)}
}
function Write-JsonResponse($res,$obj,[int]$status=200){
    $payload=$obj|ConvertTo-Json -Depth 8
    $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
    $res.StatusCode=$status
    $res.ContentType="application/json; charset=utf-8"
    $res.Headers["Access-Control-Allow-Origin"]="*"
    $res.Headers["Access-Control-Allow-Methods"]="GET, OPTIONS"
    $res.Headers["Access-Control-Allow-Headers"]="Content-Type"
    $res.Headers["Cache-Control"]="no-store, no-cache, must-revalidate, max-age=0"
    $res.ContentLength64=$bytes.Length
    $res.OutputStream.Write($bytes,0,$bytes.Length)
}

Initialize-ZoneFromTail
Reset-ToCurrentEnd

$listener=New-Object Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:8767/")
$listener.Start()

try{
    while($listener.IsListening){
        if(-not(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){break}
        Read-NewLoot
        $task=$listener.GetContextAsync()
        while(-not $task.Wait(25)){
            if(-not(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){break}
            Read-NewLoot
        }
        if(-not $task.IsCompleted){continue}
        $ctx=$task.Result
        $req=$ctx.Request
        $res=$ctx.Response
        try{
            if($req.HttpMethod -eq "OPTIONS"){$res.StatusCode=204;continue}
            if($req.Url.AbsolutePath -ne "/api/live-poll"){
                Write-JsonResponse $res ([pscustomobject]@{ok=$false;error="Not found"}) 404
                continue
            }

            Read-NewLoot
            $since=0
            [void][int]::TryParse($req.QueryString["since"],[ref]$since)
            $selected=@($events|Where-Object{$_.id -gt $since})
            $ver=Read-AppVersion
            $cfg=Read-Config
            Write-JsonResponse $res ([pscustomobject]@{
                ok=$true
                version=[string]$ver.version
                channel=[string]$ver.channel
                logPath=$logPath
                logFile=$logFileName
                character=$character
                lastEventId=$nextId-1
                position=$position
                sessionId=$currentSessionId
                currentZone=$currentZone
                currentZoneId=$currentZoneId
                currentInstanceId=$currentInstanceId
                currentZoneVersion=$currentZoneVersion
                currentZoneEnteredAt=$currentZoneEnteredAt
                observedLootHistoryEnabled=($cfg.observedLootHistoryEnabled -ne $false)
                corpseRecoveryPending=[bool]$corpseRecoveryPending
                corpseRecoveryActive=[bool]$corpseRecoveryActive
                corpseRecoveryFirstLootSeen=[bool]$corpseRecoveryFirstLootSeen
                corpseRecoveryLastLootAt=$(if($corpseRecoveryLastLootAt){$corpseRecoveryLastLootAt.ToString("o")}else{$null})
                events=$selected
                workerTime=(Get-Date).ToString("o")
            })
        }catch{
            try{Write-JsonResponse $res ([pscustomobject]@{ok=$false;error=$_.Exception.Message}) 500}catch{}
        }finally{
            try{$res.OutputStream.Close()}catch{}
        }
    }
}finally{
    try{$listener.Stop()}catch{}
    try{$listener.Close()}catch{}
}
