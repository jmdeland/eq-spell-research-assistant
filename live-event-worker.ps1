param(
    [Parameter(Mandatory=$true)][int]$ParentPid
)

$ErrorActionPreference="SilentlyContinue"
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath=Join-Path $root "monitor-config.json"
$appVersionPath=Join-Path $root "app-version.json"
$userDataRoot = if($env:EQRL_USER_DATA_ROOT){[IO.Path]::GetFullPath($env:EQRL_USER_DATA_ROOT)}else{Join-Path $env:LOCALAPPDATA "EverQuest Research & Loot Tool"}
$sessionMetaPath=Join-Path $userDataRoot "session-meta.json"
$browserStatePath=Join-Path $userDataRoot "browser-state.json"
$nativeAlertCache=@{}
$nativeAlertLastKind=""
$nativeAlertLastAt=$null

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
function Normalize-NativeAlertName([string]$value){
    if([string]::IsNullOrWhiteSpace($value)){return ""}
    $x=$value.ToLowerInvariant().Replace([char]0x2019,'`').Replace("'",'`')
    return ([regex]::Replace($x,'\s+',' ')).Trim()
}
function Build-NativeResearchUseMap {
    $map=@{}
    $precomputed=Join-Path $root 'data\native-research-use-map.json'
    if(Test-Path -LiteralPath $precomputed){
        try{
            $data=Get-Content -LiteralPath $precomputed -Raw|ConvertFrom-Json
            if($data.items){
                foreach($prop in $data.items.PSObject.Properties){
                    $keys=@($prop.Value)
                    $h=@{}
                    foreach($key in $keys){if($key){$h[[string]$key]=$true}}
                    $map[[string]$prop.Name]=$h
                }
                if($map.Count -gt 0){return $map}
            }
        }catch{}
    }

    # Safe fallback for older/custom data packs that do not include the precomputed map.
    $paths=@(
        (Join-Path $root 'data\bastion-synced-recipes.json'),
        (Join-Path $root 'data\bastion-recipes.json')
    )
    foreach($path in $paths){
        if(-not(Test-Path -LiteralPath $path)){continue}
        try{
            $data=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
            $all=@()
            if($data.recipes){$all+=@($data.recipes)}
            if($data.subcombines){$all+=@($data.subcombines)}
            foreach($recipe in $all){
                $recipeKey=[string]$(if($recipe.recipeId){$recipe.recipeId}elseif($recipe.recipeKey){$recipe.recipeKey}elseif($recipe.spell){$recipe.spell}elseif($recipe.name){$recipe.name}else{[guid]::NewGuid().ToString()})
                foreach($component in @($recipe.components)){
                    if($component.vendorBasic -eq $true){continue}
                    $name=Normalize-NativeAlertName ([string]$component.name)
                    if(-not $name){continue}
                    if(-not $map.ContainsKey($name)){$map[$name]=@{}}
                    $map[$name][$recipeKey]=$true
                }
            }
        }catch{}
    }
    return $map
}
function Read-NativeAlertSettings {
    $result=[ordered]@{
        enabled=$true
        soundHigh=$true
        soundAny=$false
        soundCraftable=$true
        threshold=5
        volume=0.65
        includeOthers=$false
        classOnly=$false
        overrides=@{}
    }
    if(Test-Path -LiteralPath $browserStatePath){
        try{
            $outer=Get-Content -LiteralPath $browserStatePath -Raw|ConvertFrom-Json
            if($outer.eqResearchLiveSettings){
                try{
                    $ls=[string]$outer.eqResearchLiveSettings|ConvertFrom-Json
                    if($null -ne $ls.enabled){$result.enabled=[bool]$ls.enabled}
                    if($null -ne $ls.soundHigh){$result.soundHigh=[bool]$ls.soundHigh}
                    if($null -ne $ls.soundAny){$result.soundAny=[bool]$ls.soundAny}
                    if($null -ne $ls.soundCraftable){$result.soundCraftable=[bool]$ls.soundCraftable}
                    if($ls.threshold){$result.threshold=[Math]::Max(1,[int]$ls.threshold)}
                    if($null -ne $ls.volume){$result.volume=[Math]::Max(0,[Math]::Min(1,[double]$ls.volume))}
                    if($null -ne $ls.includeOthers){$result.includeOthers=[bool]$ls.includeOthers}
                    if($null -ne $ls.classOnly){$result.classOnly=[bool]$ls.classOnly}
                }catch{}
            }
            if($outer.eqResearchLootValueOverridesV1){
                try{$result.overrides=[string]$outer.eqResearchLootValueOverridesV1|ConvertFrom-Json -AsHashtable}catch{
                    try{
                        $obj=[string]$outer.eqResearchLootValueOverridesV1|ConvertFrom-Json
                        $h=@{}
                        foreach($prop in $obj.PSObject.Properties){$h[$prop.Name]=$prop.Value}
                        $result.overrides=$h
                    }catch{}
                }
            }
        }catch{}
    }
    return [pscustomobject]$result
}
function Get-NativeOverride([hashtable]$overrides,[string]$item){
    if(-not $overrides){return ""}
    $key=Normalize-NativeAlertName $item
    $raw=$null
    if($overrides.ContainsKey($key)){$raw=$overrides[$key]}
    if($null -eq $raw){return ""}
    $value=$raw
    if($raw -isnot [string] -and $raw.PSObject.Properties['value']){$value=$raw.value}
    $v=([string]$value).ToUpperInvariant().Replace('_',' ').Trim()
    if(@('HIGH VALUE','KEEP','NOT VALUABLE') -contains $v){return $v}
    return ""
}
function New-NativeTonePlayer([string]$kind,[double]$volume){
    $pct=[int][Math]::Round([Math]::Max(0,[Math]::Min(1,$volume))*100)
    $cacheKey="$kind|$pct"
    if($script:nativeAlertCache.ContainsKey($cacheKey)){return $script:nativeAlertCache[$cacheKey].player}
    $plan=switch($kind){
        'high' {@(@(880,120),@(1175,160));break}
        'craftable' {@(@(740,120),@(988,120),@(1318,220));break}
        default {@(@(660,100));break}
    }
    $sampleRate=22050
    $samples=New-Object 'System.Collections.Generic.List[Int16]'
    $amp=[Math]::Round(32767.0*[Math]::Max(0.03,$volume)*0.28)
    foreach($part in $plan){
        $freq=[double]$part[0];$durationMs=[int]$part[1]
        $count=[int]($sampleRate*$durationMs/1000.0)
        for($i=0;$i -lt $count;$i++){
            $sample=[int][Math]::Round($amp*[Math]::Sin(2.0*[Math]::PI*$freq*$i/$sampleRate))
            if($sample -gt 32767){$sample=32767};if($sample -lt -32768){$sample=-32768}
            [void]$samples.Add([int16]$sample)
        }
        $gap=[int]($sampleRate*0.05)
        for($i=0;$i -lt $gap;$i++){[void]$samples.Add([int16]0)}
    }
    $dataBytes=$samples.Count*2
    $ms=New-Object IO.MemoryStream
    $bw=New-Object IO.BinaryWriter($ms)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $bw.Write([int](36+$dataBytes))
    $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
    $bw.Write([Text.Encoding]::ASCII.GetBytes('fmt '))
    $bw.Write([int]16);$bw.Write([int16]1);$bw.Write([int16]1)
    $bw.Write([int]$sampleRate);$bw.Write([int]($sampleRate*2));$bw.Write([int16]2);$bw.Write([int16]16)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('data'));$bw.Write([int]$dataBytes)
    foreach($sample in $samples){$bw.Write([int16]$sample)}
    $bw.Flush();$ms.Position=0
    $player=New-Object System.Media.SoundPlayer($ms)
    try{$player.Load()}catch{}
    $script:nativeAlertCache[$cacheKey]=[pscustomobject]@{player=$player;stream=$ms;writer=$bw}
    return $player
}
function Play-NativeAlert([string]$kind,[double]$volume){
    try{
        if($volume -le 0){return $false}
        $player=New-NativeTonePlayer $kind $volume
        if($player){$player.Play();$script:nativeAlertLastKind=$kind;$script:nativeAlertLastAt=Get-Date;return $true}
    }catch{}
    return $false
}
$nativeResearchUseMap=@{}
$workerStartedAt=Get-Date
$listenerStartedAt=$null
$workerReadyAt=$null
function Invoke-NativeLootAlert($evt){
    if(-not $evt -or $evt.corpseRecovery){return}
    $settings=Read-NativeAlertSettings
    if(-not $settings.enabled -or $settings.volume -le 0){return}
    if(-not $evt.self -and -not $settings.includeOthers){return}
    # Class-only filtering depends on the browser's selected class. Keep the
    # browser fallback for that uncommon mode rather than play an inaccurate alert.
    if($settings.classOnly){return}
    $name=Normalize-NativeAlertName ([string]$evt.item)
    $uses=0
    if($nativeResearchUseMap.ContainsKey($name)){$uses=[int]$nativeResearchUseMap[$name].Count}
    $override=Get-NativeOverride $settings.overrides ([string]$evt.item)
    if($override -eq 'NOT VALUABLE'){return}
    if($override -eq 'HIGH VALUE'){
        if($settings.soundHigh){[void](Play-NativeAlert 'high' $settings.volume)}
        return
    }
    if($uses -ge [int]$settings.threshold){
        if($settings.soundHigh){[void](Play-NativeAlert 'high' $settings.volume)}
    } elseif($uses -gt 0 -and $settings.soundAny){
        [void](Play-NativeAlert 'research' $settings.volume)
    }
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
$corpseRecoveryDeathSeenAt=$null
$corpseRecoveryStartWindowSeconds=120
$corpseRecoveryIdleWindowSeconds=60
$corpseRecoveryMaxWindowSeconds=600

function Reset-CorpseRecoveryContext {
    $script:corpseRecoveryPending=$false
    $script:corpseRecoveryActive=$false
    $script:corpseRecoveryActivatedAt=$null
    $script:corpseRecoveryLastLootAt=$null
    $script:corpseRecoveryFirstLootSeen=$false
    $script:corpseRecoveryDeathSeenAt=$null
}
function Update-CorpseRecoveryContextFromLine([string]$line){
    if(-not $line){return}

    $death=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*You have been slain by .+!\s*$')
    if($death.Success){
        Reset-CorpseRecoveryContext
        $dt=Parse-EqLogTime $death.Groups['time'].Value
        $script:corpseRecoveryDeathSeenAt=$(if($dt){$dt}else{Get-Date})
        return
    }

    $res=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*You regain experience from resurrection\.')
    if($res.Success){
        $script:corpseRecoveryPending=$true
        $script:corpseRecoveryActive=$false
        $script:corpseRecoveryActivatedAt=$null
        $script:corpseRecoveryLastLootAt=$null
        $script:corpseRecoveryFirstLootSeen=$false
        return
    }

    $returning=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*Returning to Resurrect, please wait\.\.\.\s*$')
    if($returning.Success -and $script:corpseRecoveryPending){
        $t=Parse-EqLogTime $returning.Groups['time'].Value
        $script:corpseRecoveryPending=$false
        $script:corpseRecoveryActive=$true
        $script:corpseRecoveryActivatedAt=$(if($t){$t}else{Get-Date})
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
        if($script:corpseRecoveryActive){
            $sameRezTransition=$false
            if(-not $script:corpseRecoveryFirstLootSeen -and $script:corpseRecoveryActivatedAt){
                $zt=$(if($t){$t}else{Get-Date})
                $sameRezTransition=(($zt-$script:corpseRecoveryActivatedAt).TotalSeconds -le 30)
            }
            if(-not $sameRezTransition){Reset-CorpseRecoveryContext}
        }
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
function Read-ZoneTailBytes([int64]$requestedBytes) {
    if(-not $logPath -or -not(Test-Path -LiteralPath $logPath)){return}
    try{
        $fi=Get-Item -LiteralPath $logPath
        $tailBytes=[Math]::Min([int64]$requestedBytes,[int64]$fi.Length)
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
function Initialize-ZoneFromTail {
    # Most active logs have a zone transition in the last 2 MB. This keeps startup
    # fast while retaining the prior 16 MB fallback for long quiet sessions.
    Read-ZoneTailBytes (2MB)
    if(-not $script:currentZone){Read-ZoneTailBytes (16MB)}
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
            Invoke-NativeLootAlert $evt
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

# Open the local listener before heavier initialization so callers do not see
# a connection-refused gap while the worker prepares zone and alert data.
$listener=New-Object Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:8767/")
$listener.Start()
$listenerStartedAt=Get-Date

$nativeResearchUseMap=Build-NativeResearchUseMap
Initialize-ZoneFromTail
Reset-ToCurrentEnd
$workerReadyAt=Get-Date

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
            if($req.Url.AbsolutePath -eq "/api/native-sound-test"){
                $kind=[string]$req.QueryString["kind"]
                if(@('high','research','craftable') -notcontains $kind){$kind='research'}
                $settings=Read-NativeAlertSettings
                $played=Play-NativeAlert $kind ([double]$settings.volume)
                Write-JsonResponse $res ([pscustomobject]@{ok=$true;played=[bool]$played;kind=$kind;volume=$settings.volume;native=$true}) 200
                continue
            }
            if($req.Url.AbsolutePath -eq "/api/native-alert-status"){
                $settings=Read-NativeAlertSettings
                Write-JsonResponse $res ([pscustomobject]@{ok=$true;native=$true;ready=[bool]$workerReadyAt;researchItems=$nativeResearchUseMap.Count;enabled=$settings.enabled;classOnly=$settings.classOnly;volume=$settings.volume;startupMs=$(if($workerReadyAt){[int](($workerReadyAt-$workerStartedAt).TotalMilliseconds)}else{$null});lastKind=$nativeAlertLastKind;lastAt=$(if($nativeAlertLastAt){$nativeAlertLastAt.ToString('o')}else{$null})}) 200
                continue
            }
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
                nativeAlerts=$true
                workerReady=[bool]$workerReadyAt
                workerStartupMs=$(if($workerReadyAt){[int](($workerReadyAt-$workerStartedAt).TotalMilliseconds)}else{$null})
                nativeResearchItems=$nativeResearchUseMap.Count
                nativeAlertLastKind=$nativeAlertLastKind
                nativeAlertLastAt=$(if($nativeAlertLastAt){$nativeAlertLastAt.ToString('o')}else{$null})
                corpseRecoveryPending=[bool]$corpseRecoveryPending
                corpseRecoveryActive=[bool]$corpseRecoveryActive
                corpseRecoveryFirstLootSeen=[bool]$corpseRecoveryFirstLootSeen
                corpseRecoveryLastLootAt=$(if($corpseRecoveryLastLootAt){$corpseRecoveryLastLootAt.ToString("o")}else{$null})
                corpseRecoveryDeathSeenAt=$(if($corpseRecoveryDeathSeenAt){$corpseRecoveryDeathSeenAt.ToString("o")}else{$null})
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
