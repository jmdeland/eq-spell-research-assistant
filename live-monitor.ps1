param([string]$LogPath = "")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $root "monitor-config.json"
$syncDataPath = Join-Path $root "data\bastion-synced-recipes.json"
$userDataRoot = Join-Path $env:LOCALAPPDATA "EverQuest Research & Loot Tool"
if(-not (Test-Path -LiteralPath $userDataRoot)){New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null}
$sessionStatePath = Join-Path $userDataRoot "session-loot.jsonl"
$sessionMetaPath = Join-Path $userDataRoot "session-meta.json"
$lootHistoryRoot = Join-Path $userDataRoot "history"
if(-not(Test-Path -LiteralPath $lootHistoryRoot)){New-Item -ItemType Directory -Path $lootHistoryRoot -Force | Out-Null}
$lootHistoryIndexPath = Join-Path $lootHistoryRoot "loot-history-index.json"
$legacyLootHistoryPath = Join-Path $userDataRoot "loot-history.jsonl"
$historyIndexWorkerScript = Join-Path $root "history-index-worker.ps1"
$persistenceWorkerScript = Join-Path $root "persistence-worker.ps1"
$liveEventWorkerScript = Join-Path $root "live-event-worker.ps1"
$script:liveEventWorkerProcess=$null
function Start-LiveEventWorker {
    try{
        if(Test-Path -LiteralPath $liveEventWorkerScript){
            $script:liveEventWorkerProcess=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
                "-NoProfile","-ExecutionPolicy","Bypass","-File",$liveEventWorkerScript,
                "-ParentPid",$PID
            )
        }
    }catch{}
}

$script:persistenceWorkerProcess=$null
function Start-PersistenceWorker {
    try{
        if(Test-Path -LiteralPath $persistenceWorkerScript){
            $script:persistenceWorkerProcess=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
                "-NoProfile","-ExecutionPolicy","Bypass","-File",$persistenceWorkerScript,
                "-ParentPid",$PID
            )
        }
    }catch{}
}

$script:historyIndexWorkerProcess=$null
function Start-HistoryIndexWorker {
    try{
        if(Test-Path -LiteralPath $historyIndexWorkerScript){
            $script:historyIndexWorkerProcess=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
                "-NoProfile","-ExecutionPolicy","Bypass","-File",$historyIndexWorkerScript,
                "-ParentPid",$PID
            )
        }
    }catch{}
}

$script:historyIndexCache=$null
$script:historyIndexDirty=$false
$script:lastHistoryIndexFlush=Get-Date
$trayPidPath = Join-Path $userDataRoot "tray.pid"
$shutdownRequestPath = Join-Path $userDataRoot "shutdown-for-update.request"
$suppressBrowserPath = Join-Path $userDataRoot "suppress-browser-once.request"

function Get-Config {
    if (Test-Path $configPath) {
        try { return (Get-Content $configPath -Raw | ConvertFrom-Json) } catch {}
    }
    return [pscustomobject]@{
        logPath = ""
        port = 8765
        startAtEnd = $true
        observedLootHistoryEnabled = $true
    }
}
function Save-Config($cfg) {$cfg | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8}

function Write-AtomicUtf8File([string]$Path,[string]$Content,[int]$MaxAttempts=20) {
    $dir=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}
    $tmp=Join-Path $dir (".{0}.{1}.tmp" -f [IO.Path]::GetFileName($Path),[guid]::NewGuid().ToString("N"))
    try{
        [IO.File]::WriteAllText($tmp,$Content,(New-Object Text.UTF8Encoding($false)))
        for($attempt=1;$attempt -le $MaxAttempts;$attempt++){
            try{
                if(Test-Path -LiteralPath $Path){
                    $backup=$Path+".replace-backup"
                    try{
                        [IO.File]::Replace($tmp,$Path,$backup,$true)
                        if(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue}
                    }catch{
                        # File.Replace is not available for every filesystem/path situation.
                        # Fall back to move-overwrite behavior once the destination unlocks.
                        if(Test-Path -LiteralPath $Path){Remove-Item -LiteralPath $Path -Force -ErrorAction Stop}
                        Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
                    }
                }else{
                    Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
                }
                return
            }catch{
                if($attempt -ge $MaxAttempts){throw}
                Start-Sleep -Milliseconds (100 + ($attempt * 75))
            }
        }
    }finally{
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
    }
}

function Choose-LogFile {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Choose the active EverQuest log file"
    $dlg.Filter = "EverQuest logs (eqlog_*.txt)|eqlog_*.txt|Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $dlg.Multiselect = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {return $dlg.FileName}
    return $null
}
function Strip-Html([string]$html) {
    $x=[regex]::Replace($html,'<script\b[^>]*>.*?</script>',' ','Singleline,IgnoreCase')
    $x=[regex]::Replace($x,'<style\b[^>]*>.*?</style>',' ','Singleline,IgnoreCase')
    $x=[regex]::Replace($x,'<[^>]+>',' ')
    $x=[Net.WebUtility]::HtmlDecode($x)
    return ([regex]::Replace($x,'\s+',' ')).Trim()
}
function Invoke-Bastion([string]$url) {
    return (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 45 -Headers @{"User-Agent"="EQ-Research-Loot-Tool/0.17.1-demo.1"}).Content
}
function Parse-RecipePage([int]$id,[string]$html) {
    $plain=Strip-Html $html
    $name=""
    $title=[regex]::Match($plain,'Recipe\s*-\s*(?<n>.+?)\s+Searches recipe by name','IgnoreCase')
    if($title.Success){$name=$title.Groups['n'].Value.Trim()}
    if(-not $name){
        $m=[regex]::Match($plain,'Recipe\s+(?<n>.+?)\s+Research\s*-\s*\d+\s+trivial','IgnoreCase')
        if($m.Success){$name=$m.Groups['n'].Value.Trim()}
    }
    $tm=[regex]::Match($plain,'Research\s*-\s*(?<t>\d+)\s+trivial','IgnoreCase')
    if(-not $tm.Success){return $null}
    $trivial=[int]$tm.Groups['t'].Value

    # Limit ingredient extraction to the Ingredients section.
    $ingHtml=$html
    $im=[regex]::Match($html,'Ingredients(?<body>.*?)Creates','Singleline,IgnoreCase')
    if($im.Success){$ingHtml=$im.Groups['body'].Value}

    $components=New-Object System.Collections.ArrayList
    $matches=[regex]::Matches($ingHtml,'(?<qty>\d+)\s*x(?:(?!\d+\s*x).){0,500}?href=["''][^"'']*/items/(?<id>\d+)["''][^>]*>(?<name>.*?)</a>','Singleline,IgnoreCase')
    foreach($m in $matches){
        $nm=Strip-Html $m.Groups['name'].Value
        if($nm){
            $obj=[ordered]@{name=$nm;id=[int]$m.Groups['id'].Value}
            $q=[int]$m.Groups['qty'].Value;if($q -gt 1){$obj.count=$q}
            if($nm -eq "Quill" -or $nm -eq "Piece of Parchment"){$obj.vendorBasic=$true}
            [void]$components.Add([pscustomobject]$obj)
        }
    }
    # Fallback for object/vendor basics if their item link is absent.
    foreach($basic in @("Quill","Piece of Parchment")){
        if($ingHtml -match [regex]::Escape($basic) -and -not ($components | Where-Object {$_.name -eq $basic})){
            [void]$components.Add([pscustomobject]@{name=$basic;vendorBasic=$true})
        }
    }

    if($components.Count -eq 0){return $null}
    $spellName=$name
    if($spellName -match '^Spell:\s*(.+)$'){$spellName=$Matches[1]}
    return [pscustomobject]@{
        recipeId=$id
        recipeKey="bastion:$id"
        class="ALL"
        classes=@()
        level=$null
        spell=$spellName
        trivial=$trivial
        components=@($components)
        source="Bastion synced"
        sourceUrl="https://library.bastiongame.com/recipes/$id"
        containers=@()
        notes="Synced from Bastion Research recipe index."
        verification="bastion-live-sync"
        complete=$true
        yield=1
    }
}
function Sync-BastionResearch {
    $ids=New-Object System.Collections.Generic.HashSet[int]
    $pagesScanned=0
    $discoveryMode="filtered"

    # Fast path: try Bastion's Research-filtered recipe listing.
    $page=1
    while($page -le 200){
        $url="https://library.bastiongame.com/recipes?ts=58&page=$page"
        $html=Invoke-Bastion $url
        $found=[regex]::Matches($html,'href=["''](?:https?://[^/"'']+)?/recipes/(?<id>\d+)(?:[?"''])','IgnoreCase')
        $new=0
        foreach($m in $found){if($ids.Add([int]$m.Groups['id'].Value)){$new++}}
        $pagesScanned++
        if($new -eq 0){break}
        $page++
        Start-Sleep -Milliseconds 80
    }

    # Bastion's deployed filter can differ from the repository/source assumptions.
    # If the filtered query returns no recipe links, fall back to crawling the normal
    # recipe index and selecting only table rows whose tradeskill column is Research.
    if($ids.Count -eq 0){
        $discoveryMode="full-index-fallback"
        $pagesScanned=0
        $page=1
        $seenPageSignatures=New-Object System.Collections.Generic.HashSet[string]

        while($page -le 500){
            $url="https://library.bastiongame.com/recipes?page=$page"
            $html=Invoke-Bastion $url
            $pagesScanned++

            # Identify all recipe IDs on the page so a page with no Research rows
            # does not accidentally terminate discovery.
            $allMatches=[regex]::Matches(
                $html,
                'href=["''](?:https?://[^/"'']+)?/recipes/(?<id>\d+)(?:[?"''])',
                'IgnoreCase'
            )
            $allIds=@()
            foreach($m in $allMatches){$allIds += [int]$m.Groups['id'].Value}
            $allIds=@($allIds | Select-Object -Unique)

            if($allIds.Count -eq 0){break}

            $signature=($allIds -join ",")
            if(-not $seenPageSignatures.Add($signature)){break}

            # Parse recipe table rows and keep only rows explicitly labeled Research.
            $rows=[regex]::Matches($html,'<tr\b[^>]*>(?<row>.*?)</tr>','Singleline,IgnoreCase')
            foreach($rowMatch in $rows){
                $rowHtml=$rowMatch.Groups['row'].Value
                $rowText=Strip-Html $rowHtml
                if($rowText -notmatch '(?i)\bResearch\b'){continue}

                $rm=[regex]::Match(
                    $rowHtml,
                    'href=["''](?:https?://[^/"'']+)?/recipes/(?<id>\d+)(?:[?"''])',
                    'IgnoreCase'
                )
                if($rm.Success){[void]$ids.Add([int]$rm.Groups['id'].Value)}
            }

            $page++
            Start-Sleep -Milliseconds 60
        }
    }

    $recipes=New-Object System.Collections.ArrayList
    $errors=New-Object System.Collections.ArrayList
    $n=0
    foreach($id in ($ids | Sort-Object)){
        $n++
        try{
            $html=Invoke-Bastion "https://library.bastiongame.com/recipes/$id"
            $r=Parse-RecipePage $id $html
            if($r){[void]$recipes.Add($r)}else{[void]$errors.Add("Recipe $id did not parse")}
        }catch{
            [void]$errors.Add("Recipe ${id}: $($_.Exception.Message)")
        }
        if(($n % 20)-eq 0){Start-Sleep -Milliseconds 150}
    }

    $payload=[pscustomobject]@{
        version="0.12.3-sync"
        syncedAt=(Get-Date).ToString("o")
        source=$(if($discoveryMode -eq "filtered"){"https://library.bastiongame.com/recipes?ts=58"}else{"https://library.bastiongame.com/recipes"})
        tradeskill="Research"
        discoveryMode=$discoveryMode
        pagesScanned=$pagesScanned
        recipeIdsFound=$ids.Count
        recipes=@($recipes)
        errors=@($errors)
    }
    $json=$payload | ConvertTo-Json -Depth 20
    Write-AtomicUtf8File $syncDataPath $json
    return $payload
}

$config=Get-Config
if($LogPath){$config.logPath=$LogPath}
if(-not $config.port){$config | Add-Member -NotePropertyName port -NotePropertyValue 8765 -Force}
if($null -eq $config.startAtEnd){$config | Add-Member -NotePropertyName startAtEnd -NotePropertyValue $true -Force}
if($null -eq $config.observedLootHistoryEnabled){$config | Add-Member -NotePropertyName observedLootHistoryEnabled -NotePropertyValue $true -Force;Save-Config $config}
$port=[int]$config.port

if(-not $config.logPath -or -not (Test-Path -LiteralPath $config.logPath)){
    $picked=Choose-LogFile
    if(-not $picked){Write-Host "No log file selected. Exiting.";exit 1}
    $config.logPath=$picked;Save-Config $config
}
$logPath=[string]$config.logPath
$logFileName=[IO.Path]::GetFileName($logPath)
$character=""
if($logFileName -match '^eqlog_(.+?)_[^_]+\.txt$'){$character=$Matches[1]}

$script:currentZone=""
$script:currentZoneId=$null
$script:currentInstanceId=$null
$script:currentZoneVersion=$null
$script:currentZoneEnteredAt=$null
$script:lastZoneEntryLogTime=$null
$script:currentZoneIsGenericInstance=$false

# Corpse recovery protection. A successful resurrection arms a short window for
# the first self-loot sequence after the return zone. Recovered items remain in
# the current session for transparency, but are marked so the browser/backend
# can exclude them from observed-drop history and ownership calculations.
$script:corpseRecoveryPending=$false
$script:corpseRecoveryActive=$false
$script:corpseRecoveryActivatedAt=$null
$script:corpseRecoveryLastLootAt=$null
$script:corpseRecoveryFirstLootSeen=$false
$script:corpseRecoveryStartWindowSeconds=120
$script:corpseRecoveryIdleWindowSeconds=60
$script:corpseRecoveryMaxWindowSeconds=600

function Reset-CorpseRecoveryContext {
    $script:corpseRecoveryPending=$false
    $script:corpseRecoveryActive=$false
    $script:corpseRecoveryActivatedAt=$null
    $script:corpseRecoveryLastLootAt=$null
    $script:corpseRecoveryFirstLootSeen=$false
}
function Update-CorpseRecoveryContextFromLine([string]$line) {
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
        # A second zone transition ends any unfinished recovery window.
        if($script:corpseRecoveryActive){Reset-CorpseRecoveryContext}
    }
}
function Get-CorpseRecoveryLootState([string]$timestamp) {
    if(-not $script:corpseRecoveryActive){return $false}
    $t=Parse-EqLogTime $timestamp
    if(-not $t){$t=Get-Date}

    if($script:corpseRecoveryActivatedAt){
        $age=($t-$script:corpseRecoveryActivatedAt).TotalSeconds
        if($age -gt $script:corpseRecoveryMaxWindowSeconds){
            Reset-CorpseRecoveryContext
            return $false
        }
        if(-not $script:corpseRecoveryFirstLootSeen -and $age -gt $script:corpseRecoveryStartWindowSeconds){
            Reset-CorpseRecoveryContext
            return $false
        }
    }
    if($script:corpseRecoveryFirstLootSeen -and $script:corpseRecoveryLastLootAt){
        $idle=($t-$script:corpseRecoveryLastLootAt).TotalSeconds
        if($idle -gt $script:corpseRecoveryIdleWindowSeconds){
            Reset-CorpseRecoveryContext
            return $false
        }
    }

    $script:corpseRecoveryFirstLootSeen=$true
    $script:corpseRecoveryLastLootAt=$t
    return $true
}

function Test-GenericInstanceZoneName([string]$zone) {
    if([string]::IsNullOrWhiteSpace($zone)){return $false}
    $z=$zone.Trim()
    return [regex]::IsMatch($z,'^(?:a|an)?\s*instanced\s+version\s+of\s+(?:the\s+)?zone$','IgnoreCase')
}
function Parse-EqLogTime([string]$value) {
    if([string]::IsNullOrWhiteSpace($value)){return $null}
    try{return [DateTime]::Parse($value,[Globalization.CultureInfo]::InvariantCulture)}catch{}
    try{return [DateTime]::Parse($value)}catch{}
    return $null
}
function Update-ZoneContextFromLine([string]$line) {
    if(-not $line){return $false}
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
        return $true
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
            $script:currentZone=$zone
            $script:currentZoneId=[int]$m.Groups['zoneId'].Value
            $script:currentInstanceId=[int]$m.Groups['instanceId'].Value
            $script:currentZoneVersion=[int]$m.Groups['version'].Value
            $script:currentZoneIsGenericInstance=$false
        }
        return $true
    }
    return $false
}

function Initialize-ZoneContextFromLog {
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

        # Process the tail sequentially so an instance PID following the latest
        # "You have entered ..." line enriches that zone rather than an older one.
        foreach($line in ($text -split "`r?`n")){
            [void](Update-CorpseRecoveryContextFromLine $line)
            [void](Update-ZoneContextFromLine $line)
        }
    }catch{}
}

Initialize-ZoneContextFromLog

$events=New-Object System.Collections.ArrayList
$nextId=1
$position=0L
$carry=""
$script:sessionStartPosition=0L
$script:sessionResetAt=$null
$script:metadataSyncJob=$null
try{$fi=Get-Item -LiteralPath $logPath;if($config.startAtEnd -ne $false){$position=[int64]$fi.Length}}catch{}
$script:sessionStartPosition=[int64]$position


function Parse-LootLine([string]$line) {
    if(-not $line){return $null}
    $m=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*--You have looted (?:a|an) (?<item>.+?)\.--\s*$')
    if($m.Success){
        return [pscustomobject]@{timestamp=$m.Groups['time'].Value;looter=$(if($character){$character}else{"You"});self=$true;item=$m.Groups['item'].Value;zone=$script:currentZone;zoneId=$script:currentZoneId;instanceId=$script:currentInstanceId;zoneVersion=$script:currentZoneVersion;raw=$line}
    }
    $m=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*--(?<looter>.+?) has looted (?:a|an) (?<item>.+?)\.--\s*$')
    if($m.Success){
        $l=$m.Groups['looter'].Value
        return [pscustomobject]@{timestamp=$m.Groups['time'].Value;looter=$l;self=$(if($character -and $l -eq $character){$true}else{$false});item=$m.Groups['item'].Value;zone=$script:currentZone;zoneId=$script:currentZoneId;instanceId=$script:currentInstanceId;zoneVersion=$script:currentZoneVersion;raw=$line}
    }
    return $null
}
function Read-NewLoot {
    if(-not $logPath -or -not(Test-Path -LiteralPath $logPath)){return}
    $fi=Get-Item -LiteralPath $logPath
    if($fi.Length -lt $position){
        # A real log truncation/rotation invalidates the old byte watermark.
        $position=0L
        $script:sessionStartPosition=0L
        $carry=""
    }
    if($position -lt $script:sessionStartPosition){$position=[int64]$script:sessionStartPosition;$carry=""}
    if($fi.Length -eq $position){return}
    $fs=New-Object IO.FileStream($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        [void]$fs.Seek($position,[IO.SeekOrigin]::Begin)
        $sr=New-Object IO.StreamReader($fs)
        try{$chunk=$sr.ReadToEnd();$position=$fs.Position}finally{$sr.Dispose()}
    }finally{$fs.Dispose()}
    if(-not$chunk){return}
    $chunk=$carry+$chunk;$parts=$chunk -split "`r?`n",-1
    if($chunk -notmatch "(`r`n|`n)$"){
        $carry=$parts[-1]
        if($parts.Count -gt 1){$parts=$parts[0..($parts.Count-2)]}else{$parts=@()}
    }else{$carry=""}
    foreach($line in $parts){
        [void](Update-CorpseRecoveryContextFromLine $line)
        [void](Update-ZoneContextFromLine $line)
        $evt=Parse-LootLine $line
        if($evt){
            $isCorpseRecovery=$false
            if($evt.self){$isCorpseRecovery=Get-CorpseRecoveryLootState ([string]$evt.timestamp)}
            $evt|Add-Member -NotePropertyName corpseRecovery -NotePropertyValue $isCorpseRecovery -Force
            $evt|Add-Member -NotePropertyName lootSource -NotePropertyValue $(if($isCorpseRecovery){"corpse_recovery"}else{"observed"}) -Force
            $evt|Add-Member -NotePropertyName excludeFromObservedHistory -NotePropertyValue $isCorpseRecovery -Force
            $evt|Add-Member -NotePropertyName id -NotePropertyValue $nextId -Force
            $evt|Add-Member -NotePropertyName detectedAt -NotePropertyValue ((Get-Date).ToString("o")) -Force
            [void]$events.Add($evt);$nextId++
        }
    }
    while($events.Count -gt 1000){$events.RemoveAt(0)}
}

function Get-ContentType($path){
    switch([IO.Path]::GetExtension($path).ToLowerInvariant()){
        ".html"{"text/html; charset=utf-8"} ".js"{"application/javascript; charset=utf-8"} ".json"{"application/json; charset=utf-8"} ".css"{"text/css; charset=utf-8"} ".txt"{"text/plain; charset=utf-8"} default{"application/octet-stream"}
    }
}


function Normalize-MageloCharacter([string]$value){
    $v=$(if($null -eq $value){""}else{[string]$value}); $v=$v.Trim()
    if(-not $v){return ""}
    $m=[regex]::Match($v,'characters\.bastiongame\.com/character/(?<name>[^/?#]+)','IgnoreCase')
    if($m.Success){return $m.Groups['name'].Value.ToLowerInvariant()}
    return ($v -replace '[^A-Za-z0-9_-]','').ToLowerInvariant()
}
function Decode-JsString([string]$s){
    if($null -eq $s){return ""}
    $decoded=[regex]::Replace($s,'\\u(?<hex>[0-9A-Fa-f]{4})',{
        param($m)
        [char][Convert]::ToInt32($m.Groups['hex'].Value,16)
    })
    $decoded=$decoded.Replace("\\'","'")
    $decoded=$decoded.Replace('\"','"')
    $decoded=$decoded.Replace('\/','/')
    $decoded=$decoded.Replace('\\\\','\')
    return $decoded
}

function Parse-MageloInventory([string]$html,[string]$characterName){
    $plain=Strip-Html $html
    $bankHidden=$plain -match 'bank inventory is hidden|Anonymous or Roleplay'

    # Bastion Magelo exposes the authoritative searchable inventory here:
    # $store.invSearch.load(JSON.parse('...'))
    $m=[regex]::Match(
        $html,
        "\`$store\.invSearch\.load\(JSON\.parse\('(?<payload>.*?)'\)\)",
        'Singleline,IgnoreCase'
    )

    if(-not $m.Success){
        return [pscustomobject]@{
            character=$characterName
            url="https://characters.bastiongame.com/character/$characterName"
            bankHidden=$bankHidden
            items=@()
            counts=[pscustomobject]@{
                inventory=0
                bank=0
                sharedBank=0
                gear=0
                total=0
            }
            diagnostics=[pscustomobject]@{
                strategy="invSearch-json"
                payloadFound=$false
            }
            htmlLength=$html.Length
        }
    }

    $jsonText=Decode-JsString $m.Groups['payload'].Value

    try{
        $rawItems=$jsonText | ConvertFrom-Json
    }catch{
        throw "Bastion inventory payload was found but JSON parsing failed: $($_.Exception.Message)"
    }

    # invSearch identifies each occupied slot, but does not carry the stack quantity.
    # Bastion renders the actual quantity beside each inventory icon in the page HTML.
    # Build a per-item-ID queue of rendered stack quantities and pair those occurrences
    # with the corresponding invSearch rows. If a rendered quantity is absent, the slot
    # represents one item.
    $renderedQtyById=@{}
    $renderedMatches=[regex]::Matches($html,'data-inv-item-id="(?<id>\d+)"','IgnoreCase')
    for($ri=0;$ri -lt $renderedMatches.Count;$ri++){
        $rm=$renderedMatches[$ri]
        $start=$rm.Index
        $end=$(if($ri+1 -lt $renderedMatches.Count){$renderedMatches[$ri+1].Index}else{[Math]::Min($html.Length,$start+5000)})
        $len=[Math]::Max(0,$end-$start)
        $segment=$html.Substring($start,$len)
        $qm=[regex]::Match($segment,'indicator-item[^>]*>\s*(?<qty>\d+)\s*</span>','Singleline,IgnoreCase')
        $qty=1
        if($qm.Success){
            $parsed=0
            if([int]::TryParse($qm.Groups['qty'].Value,[ref]$parsed) -and $parsed -gt 0){$qty=$parsed}
        }
        $id=[int]$rm.Groups['id'].Value
        $key=[string]$id
        if(-not $renderedQtyById.ContainsKey($key)){$renderedQtyById[$key]=New-Object System.Collections.ArrayList}
        [void]$renderedQtyById[$key].Add($qty)
    }
    $renderedQtyIndex=@{}

    $items=New-Object System.Collections.ArrayList

    foreach($x in @($rawItems)){
        if($null -eq $x.id -or -not $x.name){continue}

        $loc=[string]$x.loc
        $location=switch -Regex ($loc){
            '^bank$'       {"Bank";break}
            '^sharedbank$' {"Shared Bank";break}
            '^gear$'       {"Gear";break}
            default        {"Inventory"}
        }

        $bagSlot=$x.bagSlot
        $containerNumber=$null
        $locationLabel=$location
        if($loc -eq "bag" -and $null -ne $bagSlot){
            $slotNumber=[int]$bagSlot
            if($slotNumber -ge 22 -and $slotNumber -le 31){
                $containerNumber=$slotNumber-21
                $locationLabel="Inventory Bag $containerNumber"
            }else{
                $locationLabel="Inventory bag slot $slotNumber"
            }
        }elseif($loc -eq "bank" -and $null -ne $bagSlot){
            $slotNumber=[int]$bagSlot
            if($slotNumber -ge 2000 -and $slotNumber -le 2099){
                $containerNumber=$slotNumber-1999
                $locationLabel="Bank Bag $containerNumber"
            }else{
                $locationLabel="Bank bag slot $slotNumber"
            }
        }elseif($loc -eq "sharedbank" -and $null -ne $bagSlot){
            $locationLabel="Shared Bank Bag $bagSlot"
        }elseif($loc -eq "gear"){
            $locationLabel="Equipped"
        }

        $itemId=[int]$x.id
        $idKey=[string]$itemId
        $quantity=1
        if($renderedQtyById.ContainsKey($idKey)){
            $qi=$(if($renderedQtyIndex.ContainsKey($idKey)){[int]$renderedQtyIndex[$idKey]}else{0})
            $qList=$renderedQtyById[$idKey]
            if($qi -lt $qList.Count){$quantity=[int]$qList[$qi]}
            $renderedQtyIndex[$idKey]=$qi+1
        }

        [void]$items.Add([pscustomobject]@{
            source="Magelo"
            character=$characterName
            location=$location
            locationLabel=$locationLabel
            containerNumber=$containerNumber
            rawLocation=$loc
            name=[string]$x.name
            id=$itemId
            count=$quantity
            bagSlot=$bagSlot
            parentId=$x.parentId
        })
    }

    # Bastion emits one invSearch row per occupied slot. The rendered inventory card
    # supplies the stack quantity for that slot. Aggregate exact item IDs by location.
    $agg=@{}
    foreach($item in $items){
        $key="$($item.location)|$($item.id)"
        if(-not $agg.ContainsKey($key)){
            $agg[$key]=[pscustomobject]@{
                source="Magelo"
                character=$characterName
                location=$item.location
                name=$item.name
                id=$item.id
                count=0
            }
        }
        $agg[$key].count += [int]$item.count
    }

    return [pscustomobject]@{
        character=$characterName
        url="https://characters.bastiongame.com/character/$characterName"
        bankHidden=$bankHidden
        items=@($agg.Values)
        placements=@($items)
        counts=[pscustomobject]@{
            inventory=@($agg.Values|Where-Object{$_.location -eq "Inventory"}).Count
            bank=@($agg.Values|Where-Object{$_.location -eq "Bank"}).Count
            sharedBank=@($agg.Values|Where-Object{$_.location -eq "Shared Bank"}).Count
            gear=@($agg.Values|Where-Object{$_.location -eq "Gear"}).Count
            total=@($agg.Values).Count
        }
        diagnostics=[pscustomobject]@{
            strategy="invSearch-json"
            payloadFound=$true
            rawRows=@($rawItems).Count
            aggregatedRows=@($agg.Values).Count
        }
        htmlLength=$html.Length
    }
}



$updateRepo="jmdeland/eq-spell-research-assistant"
$updateApi="https://api.github.com/repos/$updateRepo/releases/latest"
$updateStage=Join-Path $root "_updates"
function Get-AppVersionInfo {
    $versionPath=Join-Path $root "app-version.json"
    if(Test-Path -LiteralPath $versionPath){
        try{return (Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json)}catch{}
    }
    return [pscustomobject]@{version="0.16.0";channel="stable"}
}
function Convert-VersionCore([string]$version){
    $clean=($version -replace '^v','').Split('-')[0]
    $parts=@($clean.Split('.') | ForEach-Object { $n=0; if([int]::TryParse($_,[ref]$n)){$n}else{0} })
    while($parts.Count -lt 3){$parts += 0}
    return [version]("{0}.{1}.{2}" -f $parts[0],$parts[1],$parts[2])
}
function Get-LatestGitHubRelease {
    $headers=@{"User-Agent"="EQ-Research-Loot-Tool/0.17.1-demo.1";"Accept"="application/vnd.github+json"}
    return Invoke-RestMethod -UseBasicParsing -Uri $updateApi -TimeoutSec 45 -Headers $headers
}
function Get-UpdateInfo {
    $installed=Get-AppVersionInfo
    $release=Get-LatestGitHubRelease
    $asset=@($release.assets | Where-Object {$_.name -match '^eq_spell_research_assistant_v.+\.zip$'} | Select-Object -First 1)
    if(-not $asset -or $asset.Count -eq 0){throw "Latest GitHub release has no updater-compatible ZIP asset."}
    $asset=$asset[0]
    $latestVersion=([string]$release.tag_name -replace '^v','')
    $stableInstalled=if($installed.stableBaseVersion){[string]$installed.stableBaseVersion}else{([string]$installed.version -replace '-.*$','')}
    $available=((Convert-VersionCore $latestVersion) -gt (Convert-VersionCore $stableInstalled))
    $digest=[string]$asset.digest
    $sha=""
    if($digest -match '^sha256:(?<h>[0-9a-fA-F]{64})$'){$sha=$Matches['h'].ToLowerInvariant()}
    return [pscustomobject]@{
        ok=$true
        installedVersion=[string]$installed.version
        installedStableVersion=$stableInstalled
        channel=[string]$installed.channel
        latestVersion=$latestVersion
        latestTag=[string]$release.tag_name
        name=[string]$release.name
        body=[string]$release.body
        releaseUrl=[string]$release.html_url
        publishedAt=[string]$release.published_at
        updateAvailable=$available
        assetName=[string]$asset.name
        assetUrl=[string]$asset.browser_download_url
        assetSize=[long]$asset.size
        expectedSha256=$sha
    }
}
function Download-AndVerifyLatestUpdate {
    $info=Get-UpdateInfo
    if(-not $info.expectedSha256){throw "GitHub did not provide a SHA-256 digest for the release asset; refusing unverified download."}
    if(-not(Test-Path -LiteralPath $updateStage)){New-Item -ItemType Directory -Path $updateStage | Out-Null}
    $dest=Join-Path $updateStage $info.assetName
    $tmp=$dest+".download"
    if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}
    $headers=@{"User-Agent"="EQ-Research-Loot-Tool/0.17.1-demo.1"}
    try{
        Invoke-WebRequest -UseBasicParsing -Uri $info.assetUrl -OutFile $tmp -TimeoutSec 120 -Headers $headers
        $actual=(Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        if($actual -ne $info.expectedSha256){throw ("SHA-256 mismatch. Expected {0}; got {1}." -f $info.expectedSha256,$actual)}
        if(Test-Path -LiteralPath $dest){Remove-Item -LiteralPath $dest -Force}
        Move-Item -LiteralPath $tmp -Destination $dest
        $size=(Get-Item -LiteralPath $dest).Length
        $sizeText=if($size -ge 1MB){"{0:N2} MB" -f ($size/1MB)}else{"{0:N0} KB" -f ($size/1KB)}
        return [pscustomobject]@{ok=$true;fileName=$info.assetName;path=$dest;sha256=$actual;size=$size;sizeText=$sizeText;latestTag=$info.latestTag}
    }catch{
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
        throw
    }
}


function Get-UpdateState {
    $result=$null
    $resultPath=Join-Path $root "update-result.json"
    if(Test-Path -LiteralPath $resultPath){try{$result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json}catch{}}
    $parent=Split-Path -Parent $root
    $leaf=Split-Path -Leaf $root
    $backups=@()
    try{
        $backups=@(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue |
            Where-Object {$_.Name -like ($leaf + "_backup_*")} |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10 |
            ForEach-Object {[pscustomobject]@{path=$_.FullName;name=$_.Name;lastWriteTime=$_.LastWriteTime.ToString("o")}})
    }catch{}
    return [pscustomobject]@{ok=$true;result=$result;backups=$backups}
}

function Start-SafeVerifiedUpdate {
    $info=Get-UpdateInfo
    if(-not $info.expectedSha256){throw "GitHub did not provide a SHA-256 digest; refusing install."}
    $zipPath=Join-Path $updateStage $info.assetName
    if(-not(Test-Path -LiteralPath $zipPath)){throw "Verified update ZIP is not staged. Download and verify it first."}
    $actual=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $info.expectedSha256){throw ("Staged ZIP is no longer valid. Expected {0}; got {1}. Download it again." -f $info.expectedSha256,$actual)}

    $parent=Split-Path -Parent $root
    $leaf=Split-Path -Leaf $root
    $stamp=Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath=Join-Path $parent ($leaf + "_backup_" + $stamp)
    if(Test-Path -LiteralPath $backupPath){throw "Backup path already exists: $backupPath"}

    $updaterPath=Join-Path $env:TEMP ("EQSpellResearchUpdater_" + [guid]::NewGuid().ToString("N") + ".ps1")
    $pidToWait=$PID
    $trayPidToWait=0
    if(Test-Path -LiteralPath $trayPidPath){
        try{$trayPidToWait=[int](Get-Content -LiteralPath $trayPidPath -Raw).Trim()}catch{$trayPidToWait=0}
    }
    Set-Content -LiteralPath $shutdownRequestPath -Value ((Get-Date).ToString("o")) -Encoding ASCII
    $script=@'
param(
 [Parameter(Mandatory=$true)][string]$Root,
 [Parameter(Mandatory=$true)][string]$ZipPath,
 [Parameter(Mandatory=$true)][string]$ExpectedSha256,
 [Parameter(Mandatory=$true)][string]$BackupPath,
 [Parameter(Mandatory=$true)][int]$WaitForPid,
 [int]$WaitForTrayPid=0,
 [Parameter(Mandatory=$true)][string]$LatestTag
)
$ErrorActionPreference="Stop"
$work=Join-Path $env:TEMP ("EQSpellResearchInstall_" + [guid]::NewGuid().ToString("N"))
$backupMade=$false
$logPath=$BackupPath + ".updater.log"
$userDataRoot=Join-Path $env:LOCALAPPDATA "EverQuest Research & Loot Tool"
if(-not(Test-Path -LiteralPath $userDataRoot)){New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null}
$suppressBrowserPath=Join-Path $userDataRoot "suppress-browser-once.request"
function Write-UpdaterLog([string]$Message){
    try{Add-Content -LiteralPath $logPath -Value ((Get-Date).ToString("o") + " " + $Message) -Encoding UTF8}catch{}
}
try {
    Set-Location -LiteralPath $env:TEMP
    Write-UpdaterLog ("Updater started. Root={0}; Zip={1}; Backup={2}" -f $Root,$ZipPath,$BackupPath)
    for($i=0;$i -lt 160;$i++){
        $monitorAlive=$null -ne (Get-Process -Id $WaitForPid -ErrorAction SilentlyContinue)
        $trayAlive=$false
        if($WaitForTrayPid -gt 0){$trayAlive=$null -ne (Get-Process -Id $WaitForTrayPid -ErrorAction SilentlyContinue)}
        if(-not $monitorAlive -and -not $trayAlive){break}
        Start-Sleep -Milliseconds 250
    }
    if(Get-Process -Id $WaitForPid -ErrorAction SilentlyContinue){throw "The running companion did not exit in time."}
    if($WaitForTrayPid -gt 0 -and (Get-Process -Id $WaitForTrayPid -ErrorAction SilentlyContinue)){throw "The system tray companion did not exit in time."}

    $actual=(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $ExpectedSha256.ToLowerInvariant()){throw "SHA-256 verification failed immediately before install."}

    New-Item -ItemType Directory -Path $work | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $work -Force
    $children=@(Get-ChildItem -LiteralPath $work -Force)
    if($children.Count -eq 1 -and $children[0].PSIsContainer){$payload=$children[0].FullName}else{$payload=$work}
    if(-not(Test-Path -LiteralPath (Join-Path $payload "START-LIVE-MONITOR.bat"))){throw "Update package does not contain START-LIVE-MONITOR.bat at its application root."}

    $preservedConfig=$null
    $configPath=Join-Path $Root "monitor-config.json"
    if(Test-Path -LiteralPath $configPath){$preservedConfig=Get-Content -LiteralPath $configPath -Raw}

    Write-UpdaterLog "Companion exited and package verified. Copying current application contents to rollback backup."
    if(Test-Path -LiteralPath $BackupPath){Remove-Item -LiteralPath $BackupPath -Recurse -Force -ErrorAction SilentlyContinue}
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    Get-ChildItem -LiteralPath $Root -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $BackupPath -Recurse -Force
    }
    $backupMade=$true

    # Keep the active root directory itself in place. This avoids Windows
    # Explorer following a renamed/moved install folder into the backup path.
    Write-UpdaterLog "Backup copy completed. Replacing application contents in-place."
    Get-ChildItem -LiteralPath $Root -Force | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
    Get-ChildItem -LiteralPath $payload -Force | ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination $Root -Force
    }
    if($preservedConfig -ne $null){Set-Content -LiteralPath (Join-Path $Root "monitor-config.json") -Value $preservedConfig -Encoding UTF8}

    $result=[pscustomobject]@{
        ok=$true
        installedTag=$LatestTag
        backupPath=$BackupPath
        installedAt=(Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 4
    $result | Set-Content -LiteralPath (Join-Path $Root "update-result.json") -Encoding UTF8

    # Keep only the two newest sibling backups for this installation path.
    try {
        $rootParent=Split-Path -Parent $Root
        $rootLeaf=Split-Path -Leaf $Root
        $matching=@(Get-ChildItem -LiteralPath $rootParent -Directory -ErrorAction SilentlyContinue |
            Where-Object {$_.Name -like ($rootLeaf + "_backup_*")} |
            Sort-Object LastWriteTime -Descending)
        if($matching.Count -gt 2){
            @($matching | Select-Object -Skip 2) | ForEach-Object {
                Write-UpdaterLog ("Removing old backup by retention policy: " + $_.FullName)
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { Write-UpdaterLog ("Backup retention warning: " + $_.Exception.Message) }

    # Rebuild the normal desktop shortcut so it always points at the newly
    # installed application root rather than an older extracted copy.
    try {
        $desktop=[Environment]::GetFolderPath('Desktop')
        $shortcutPath=Join-Path $desktop 'EverQuest Research & Loot Tool.lnk'
        $vbs=Join-Path $Root 'EverQuest Research & Loot Tool.vbs'
        $icon=Join-Path $Root 'EverQuestResearchLoot.ico'
        $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
        if(Test-Path -LiteralPath $shortcutPath){Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue}
        $ws=New-Object -ComObject WScript.Shell
        $sc=$ws.CreateShortcut($shortcutPath)
        $sc.TargetPath=$wscript
        $sc.Arguments='"'+$vbs+'"'
        $sc.WorkingDirectory=$env:TEMP
        $sc.IconLocation=$icon+',0'
        $sc.Description='Launch EverQuest Research & Loot Tool'
        $sc.Save()
        Set-Content -LiteralPath (Join-Path $userDataRoot 'install-root.txt') -Value $Root -Encoding UTF8
        Write-UpdaterLog ("Desktop shortcut refreshed to: " + $vbs)
    } catch {
        Write-UpdaterLog ("Desktop shortcut refresh warning: " + $_.Exception.Message)
    }

    $vbs=Join-Path $Root "EverQuest Research & Loot Tool.vbs"
    $wscript=Join-Path $env:WINDIR "System32\wscript.exe"
    Set-Content -LiteralPath $suppressBrowserPath -Value ((Get-Date).ToString("o")) -Encoding ASCII
    Write-UpdaterLog "Install completed. Restarting application directly through wscript.exe without cmd.exe."
    if(-not(Test-Path -LiteralPath $vbs)){throw "Updated VBS launcher was not found."}
    Start-Process -FilePath $wscript -ArgumentList @(('"{0}"' -f $vbs)) -WorkingDirectory $env:TEMP
} catch {
    $message=$_.Exception.Message
    Write-UpdaterLog ("INSTALL FAILED: " + $message)
    try {
        if($backupMade -and (Test-Path -LiteralPath $BackupPath)){
            if(-not(Test-Path -LiteralPath $Root)){New-Item -ItemType Directory -Path $Root -Force | Out-Null}
            Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            Get-ChildItem -LiteralPath $BackupPath -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $Root -Recurse -Force
            }
            Write-UpdaterLog "Rollback restored the original application contents in-place."
        }
        $err=[pscustomobject]@{ok=$false;error=$message;failedAt=(Get-Date).ToString("o")} | ConvertTo-Json -Depth 4
        if(Test-Path -LiteralPath $Root){
            $err | Set-Content -LiteralPath (Join-Path $Root "update-result.json") -Encoding UTF8
            $rollbackVbs=Join-Path $Root "EverQuest Research & Loot Tool.vbs"
            if(Test-Path -LiteralPath $rollbackVbs){
                $wscript=Join-Path $env:WINDIR "System32\wscript.exe"
                Set-Content -LiteralPath $suppressBrowserPath -Value ((Get-Date).ToString("o")) -Encoding ASCII
                Start-Process -FilePath $wscript -ArgumentList @(('"{0}"' -f $rollbackVbs)) -WorkingDirectory $env:TEMP
            }
        }
    } catch { Write-UpdaterLog ("ROLLBACK ERROR: " + $_.Exception.Message) }
} finally {
    if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
}
'@
    Set-Content -LiteralPath $updaterPath -Value $script -Encoding UTF8
    $updaterArgs=@(
        "-NoProfile","-ExecutionPolicy","Bypass",
        "-File",('"{0}"' -f $updaterPath),
        "-Root",('"{0}"' -f $root),
        "-ZipPath",('"{0}"' -f $zipPath),
        "-ExpectedSha256",('"{0}"' -f $info.expectedSha256),
        "-BackupPath",('"{0}"' -f $backupPath),
        "-WaitForPid",$pidToWait,
        "-WaitForTrayPid",$trayPidToWait,
        "-LatestTag",('"{0}"' -f $info.latestTag)
    )
    Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $env:TEMP -ArgumentList $updaterArgs
    return [pscustomobject]@{ok=$true;latestTag=$info.latestTag;backupPath=$backupPath;zipPath=$zipPath;sha256=$actual;trayPid=$trayPidToWait}
}



function Save-SessionIdentity {
    $payload=[pscustomobject]@{
        sessionId=[string]$script:sessionId
        createdAt=[string]$script:sessionCreatedAt
    }
    $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sessionMetaPath -Encoding UTF8
}
function Initialize-SessionIdentity {
    if(Test-Path -LiteralPath $sessionMetaPath){
        try{
            $m=Get-Content -LiteralPath $sessionMetaPath -Raw | ConvertFrom-Json
            if($m.sessionId){
                $script:sessionId=[string]$m.sessionId
                $script:sessionCreatedAt=$(if($m.createdAt){[string]$m.createdAt}else{(Get-Date).ToString("o")})
                return
            }
        }catch{}
    }
    $script:sessionId=[guid]::NewGuid().ToString("N")
    $script:sessionCreatedAt=(Get-Date).ToString("o")
    Save-SessionIdentity
}
function Rotate-SessionIdentity {
    $script:sessionId=[guid]::NewGuid().ToString("N")
    $script:sessionCreatedAt=(Get-Date).ToString("o")
    Save-SessionIdentity
    return $script:sessionId
}
function Test-SessionIdentity([string]$clientSessionId) {
    return (-not [string]::IsNullOrWhiteSpace($clientSessionId)) -and ($clientSessionId -eq [string]$script:sessionId)
}
function Register-StaleSessionWrite([string]$clientSessionId,[int]$count) {
    $script:staleSessionRejects++
    $script:lastRejectedSessionId=$(if($clientSessionId){$clientSessionId}else{"<missing>"})
    $script:lastRejectedAt=(Get-Date).ToString("o")
    return [pscustomobject]@{
        ok=$false
        staleSession=$true
        error="This loot write belongs to a closed or unknown session."
        rejectedCount=$count
        submittedSessionId=$(if($clientSessionId){$clientSessionId}else{$null})
        currentSessionId=[string]$script:sessionId
    }
}

function Read-RequestJson($req) {
    $reader=New-Object IO.StreamReader($req.InputStream,$req.ContentEncoding)
    try{$raw=$reader.ReadToEnd()}finally{$reader.Dispose()}
    if(-not $raw){return $null}
    return ($raw | ConvertFrom-Json)
}
$script:staleSessionRejects=0
$script:lastRejectedSessionId=$null
$script:lastRejectedAt=$null
Initialize-SessionIdentity



function Normalize-HistoryKey([string]$value) {
    if($null -eq $value){return ""}
    return ([regex]::Replace($value.Trim().ToLowerInvariant(),'\s+',' '))
}
function Get-HistoryMonthKey($evt) {
    $dt=$null
    foreach($candidate in @($evt.recordedAt,$evt.historyRecordedAt,$evt.timestamp)){
        if($candidate){try{$dt=[DateTime]::Parse([string]$candidate);break}catch{}}
    }
    if(-not $dt){$dt=Get-Date}
    return $dt.ToString("yyyy-MM")
}
function Get-HistoryIndex {
    if(Test-Path -LiteralPath $lootHistoryIndexPath){
        try{
            $fi=Get-Item -LiteralPath $lootHistoryIndexPath
            $stamp=[string]$fi.LastWriteTimeUtc.Ticks
            if($script:historyIndexCache -and $script:historyIndexCacheStamp -eq $stamp){return $script:historyIndexCache}
            $x=Get-Content -LiteralPath $lootHistoryIndexPath -Raw|ConvertFrom-Json
            if($x){
                $script:historyIndexCache=$x
                $script:historyIndexCacheStamp=$stamp
                return $script:historyIndexCache
            }
        }catch{}
    }
    if(-not $script:historyIndexCache){
        $script:historyIndexCache=[pscustomobject]@{schema=1;totalEvents=0;totalBytes=0;oldest=$null;newest=$null;months=[pscustomobject]@{};items=[pscustomobject]@{};zones=[pscustomobject]@{};looters=[pscustomobject]@{};updatedAt=$null}
    }
    return $script:historyIndexCache
}
function Flush-HistoryIndex([bool]$Force=$false) {
    if(-not $script:historyIndexDirty -or -not $script:historyIndexCache){return}
    $elapsed=((Get-Date)-$script:lastHistoryIndexFlush).TotalSeconds
    if(-not $Force -and $elapsed -lt 5){return}
    try{
        $script:historyIndexCache.updatedAt=(Get-Date).ToString("o")
        Write-AtomicUtf8File $lootHistoryIndexPath ($script:historyIndexCache|ConvertTo-Json -Depth 15)
        $script:historyIndexDirty=$false
        $script:lastHistoryIndexFlush=Get-Date
    }catch{}
}
function Ensure-NoteProperty($obj,[string]$name,$value) {
    if($null -eq $obj.PSObject.Properties[$name]){$obj|Add-Member -NotePropertyName $name -NotePropertyValue $value -Force}
    return $obj.PSObject.Properties[$name].Value
}
function Add-MonthToArrayProperty($obj,[string]$name,[string]$month) {
    $arr=@();if($obj.PSObject.Properties[$name]){$arr=@($obj.PSObject.Properties[$name].Value)}
    if($arr -notcontains $month){$obj|Add-Member -NotePropertyName $name -NotePropertyValue @($arr+$month) -Force}
}
function Update-HistoryIndex($events,[hashtable]$monthBytes) {
    $index=Get-HistoryIndex
    foreach($n in @("months","items","zones","looters")){if($null -eq $index.PSObject.Properties[$n]){$index|Add-Member -NotePropertyName $n -NotePropertyValue ([pscustomobject]@{}) -Force}}
    foreach($evt in @($events)){
        if($null -eq $evt){continue}
        $month=Get-HistoryMonthKey $evt
        $index.totalEvents=[int64]$index.totalEvents+1
        $when=[string]$(if($evt.timestamp){$evt.timestamp}else{$evt.recordedAt})
        if(-not $index.oldest){$index.oldest=$when};$index.newest=$when
        $mo=Ensure-NoteProperty $index.months $month ([pscustomobject]@{count=0;bytes=0});$mo.count=[int64]$mo.count+1
        $ik=Normalize-HistoryKey ([string]$evt.item)
        if($ik){
            $io=Ensure-NoteProperty $index.items $ik ([pscustomobject]@{name=[string]$evt.item;count=0;firstSeen=$when;lastSeen=$when;months=@()})
            $io.count=[int64]$io.count+1;if(-not $io.firstSeen){$io.firstSeen=$when};$io.lastSeen=$when;Add-MonthToArrayProperty $io "months" $month
        }
        $zone=[string]$(if($evt.zone){$evt.zone}else{"Unknown"});$zk=Normalize-HistoryKey $zone
        $zo=Ensure-NoteProperty $index.zones $zk ([pscustomobject]@{name=$zone;count=0;months=@()});$zo.count=[int64]$zo.count+1;Add-MonthToArrayProperty $zo "months" $month
        $looter=[string]$(if($evt.looter){$evt.looter}else{"Unknown"});$lk=Normalize-HistoryKey $looter
        $lo=Ensure-NoteProperty $index.looters $lk ([pscustomobject]@{name=$looter;count=0;months=@()});$lo.count=[int64]$lo.count+1;Add-MonthToArrayProperty $lo "months" $month
    }
    foreach($m in $monthBytes.Keys){
        $mo=Ensure-NoteProperty $index.months $m ([pscustomobject]@{count=0;bytes=0});$mo.bytes=[int64]$mo.bytes+[int64]$monthBytes[$m];$index.totalBytes=[int64]$index.totalBytes+[int64]$monthBytes[$m]
    }
    $index.updatedAt=(Get-Date).ToString("o")
    $script:historyIndexCache=$index
    $script:historyIndexDirty=$true
}
function Append-LootHistoryEvents($items) {
    if($config.observedLootHistoryEnabled -eq $false){return 0}
    $batch=@($items);if($batch.Count -eq 0){return 0}
    $byMonth=@{}
    foreach($evt in $batch){
        if($null -eq $evt){continue}
        if(($evt.PSObject.Properties["excludeFromObservedHistory"] -and $evt.excludeFromObservedHistory) -or ($evt.PSObject.Properties["corpseRecovery"] -and $evt.corpseRecovery)){continue}
        if(-not $evt.historyId){$evt|Add-Member -NotePropertyName historyId -NotePropertyValue ([guid]::NewGuid().ToString("N")) -Force}
        if(-not $evt.historyRecordedAt){$evt|Add-Member -NotePropertyName historyRecordedAt -NotePropertyValue ((Get-Date).ToString("o")) -Force}
        $month=Get-HistoryMonthKey $evt
        if(-not $byMonth.ContainsKey($month)){$byMonth[$month]=New-Object System.Collections.Generic.List[string]}
        $byMonth[$month].Add(($evt|ConvertTo-Json -Depth 10 -Compress))
    }
    $bytes=@{};$written=0
    foreach($month in $byMonth.Keys){
        $path=Join-Path $lootHistoryRoot ("loot-history-"+$month+".jsonl");$lines=$byMonth[$month].ToArray()
        if($lines.Count -gt 0){Add-Content -LiteralPath $path -Value $lines -Encoding UTF8;$written+=$lines.Count;$bytes[$month]=([Text.Encoding]::UTF8.GetByteCount(($lines -join "`r`n"))+2)}
    }
    # Raw observations are the source of truth. A separate worker watches the
    # monthly archives and maintains the compact index out-of-process so Live
    # Loot recognition is never blocked by index maintenance.
    return $written
}
function Get-HistoryCandidateMonths([string]$item,[string]$zone,[string]$looter) {
    $index=Get-HistoryIndex;$sets=New-Object System.Collections.ArrayList
    if($item){
        $q=Normalize-HistoryKey $item;$months=New-Object System.Collections.Generic.HashSet[string]
        foreach($p in @($index.items.PSObject.Properties)){if($p.Name -like ("*"+$q+"*")){foreach($m in @($p.Value.months)){[void]$months.Add([string]$m)}}};[void]$sets.Add($months)
    }
    if($zone -and $zone -ne "ALL"){$k=Normalize-HistoryKey $zone;$months=New-Object System.Collections.Generic.HashSet[string];if($index.zones.PSObject.Properties[$k]){foreach($m in @($index.zones.PSObject.Properties[$k].Value.months)){[void]$months.Add([string]$m)}};[void]$sets.Add($months)}
    if($looter -and $looter -ne "ALL"){$k=Normalize-HistoryKey $looter;$months=New-Object System.Collections.Generic.HashSet[string];if($index.looters.PSObject.Properties[$k]){foreach($m in @($index.looters.PSObject.Properties[$k].Value.months)){[void]$months.Add([string]$m)}};[void]$sets.Add($months)}
    if($sets.Count -eq 0){return @(Get-ChildItem -LiteralPath $lootHistoryRoot -Filter "loot-history-????-??.jsonl" -File -ErrorAction SilentlyContinue|ForEach-Object{$_.BaseName.Substring(13)}|Sort-Object -Descending)}
    $candidate=@($sets[0]);for($i=1;$i -lt $sets.Count;$i++){$candidate=@($candidate|Where-Object{$sets[$i].Contains($_)})};return @($candidate|Sort-Object -Descending)
}
function Test-HistoryEventFilter($evt,[string]$item,[string]$zone,[string]$looter,[string]$value) {
    if($item -and (Normalize-HistoryKey ([string]$evt.item)) -notlike ("*"+(Normalize-HistoryKey $item)+"*")){return $false}
    if($zone -and $zone -ne "ALL" -and [string]$evt.zone -ne $zone){return $false}
    if($looter -and $looter -ne "ALL" -and [string]$evt.looter -ne $looter){return $false}
    $rv=[string]$(if($evt.researchValue){$evt.researchValue}else{"OTHER"})
    if($value -eq "RESEARCH"){if(-not(([int]$evt.verifiedUses -gt 0) -or $rv -in @("HIGH VALUE","KEEP","UNKNOWN"))){return $false}}
    elseif($value -and $value -ne "ALL" -and $rv -ne $value){return $false}
    return $true
}
function Get-LootHistory([int]$Limit=5000,[string]$item="",[string]$zone="ALL",[string]$looter="ALL",[string]$value="ALL") {
    if($Limit -lt 1){$Limit=1};if($Limit -gt 10000){$Limit=10000}
    $rows=New-Object System.Collections.ArrayList
    foreach($month in (Get-HistoryCandidateMonths $item $zone $looter)){
        if($rows.Count -ge $Limit){break}
        $path=Join-Path $lootHistoryRoot ("loot-history-"+$month+".jsonl");if(-not(Test-Path -LiteralPath $path)){continue}
        $lines=Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
        for($i=$lines.Count-1;$i -ge 0 -and $rows.Count -lt $Limit;$i--){if(-not [string]::IsNullOrWhiteSpace($lines[$i])){try{$evt=$lines[$i]|ConvertFrom-Json;if(Test-HistoryEventFilter $evt $item $zone $looter $value){[void]$rows.Add($evt)}}catch{}}}
    }
    $index=Get-HistoryIndex;$archiveCount=@(Get-ChildItem -LiteralPath $lootHistoryRoot -Filter "loot-history-????-??.jsonl" -File -ErrorAction SilentlyContinue).Count
    return [pscustomobject]@{ok=$true;enabled=($config.observedLootHistoryEnabled -ne $false);events=@($rows);returned=$rows.Count;limit=$Limit;totalEvents=[int64]$index.totalEvents;totalItems=@($index.items.PSObject.Properties).Count;totalZones=@($index.zones.PSObject.Properties).Count;totalLooters=@($index.looters.PSObject.Properties).Count;totalBytes=[int64]$index.totalBytes;archiveCount=$archiveCount;oldest=$index.oldest;newest=$index.newest;historyRoot=$lootHistoryRoot}
}
function Rebuild-HistoryIndex {
    try{
        if($script:historyIndexWorkerProcess -and -not $script:historyIndexWorkerProcess.HasExited){
            Stop-Process -Id $script:historyIndexWorkerProcess.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 200
        }
    }catch{}

    $workerStatePath=Join-Path $lootHistoryRoot "history-index-worker-state.json"
    if(Test-Path -LiteralPath $workerStatePath){Remove-Item -LiteralPath $workerStatePath -Force -ErrorAction SilentlyContinue}
    $script:historyIndexCache=$null
    $script:historyIndexCacheStamp=$null
    $script:historyIndexDirty=$false

    $blank=[pscustomobject]@{schema=1;totalEvents=0;totalBytes=0;oldest=$null;newest=$null;months=[pscustomobject]@{};items=[pscustomobject]@{};zones=[pscustomobject]@{};looters=[pscustomobject]@{};updatedAt=$null}
    Write-AtomicUtf8File $lootHistoryIndexPath ($blank|ConvertTo-Json -Depth 10)
    $script:historyIndexCache=$blank

    foreach($file in @(Get-ChildItem -LiteralPath $lootHistoryRoot -Filter "loot-history-????-??.jsonl" -File -ErrorAction SilentlyContinue|Sort-Object Name)){
        $events=New-Object System.Collections.ArrayList
        foreach($line in (Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)){
            if(-not [string]::IsNullOrWhiteSpace($line)){try{[void]$events.Add(($line|ConvertFrom-Json))}catch{}}
        }
        $mb=@{}
        $mb[$file.BaseName.Substring(13)]=$file.Length
        if($events.Count -gt 0){Update-HistoryIndex @($events) $mb}
    }
    Flush-HistoryIndex $true
    $result=Get-HistoryIndex
    Start-HistoryIndexWorker
    return $result
}


function Migrate-LegacyLootHistory {
    if(-not(Test-Path -LiteralPath $legacyLootHistoryPath)){return}
    $backup=$legacyLootHistoryPath+".migrated-v0.17.0.bak"
    try{
        $events=New-Object System.Collections.ArrayList
        foreach($line in (Get-Content -LiteralPath $legacyLootHistoryPath -ErrorAction Stop)){
            if(-not [string]::IsNullOrWhiteSpace($line)){try{[void]$events.Add(($line|ConvertFrom-Json))}catch{}}
        }
        if($events.Count -gt 0){
            $wasEnabled=$config.observedLootHistoryEnabled
            try{
                $config.observedLootHistoryEnabled=$true
                [void](Append-LootHistoryEvents @($events))
            }finally{
                $config.observedLootHistoryEnabled=$wasEnabled
            }
        }
        if(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue}
        Move-Item -LiteralPath $legacyLootHistoryPath -Destination $backup -Force
    }catch{
        # Preserve the original file untouched if migration cannot complete.
    }
}
Migrate-LegacyLootHistory

function Get-SessionState {
    $base=[ordered]@{
        ok=$true
        sessionId=[string]$script:sessionId
        sessionCreatedAt=[string]$script:sessionCreatedAt
        hasSession=$false
        events=@()
        savedAt=$null
        staleSessionRejects=[int]$script:staleSessionRejects
        lastRejectedSessionId=$script:lastRejectedSessionId
        lastRejectedAt=$script:lastRejectedAt
    }
    if(-not(Test-Path -LiteralPath $sessionStatePath)){return [pscustomobject]$base}
    try{
        $rows=New-Object System.Collections.ArrayList
        $last=$null
        foreach($line in (Get-Content -LiteralPath $sessionStatePath -ErrorAction Stop)){
            if(-not [string]::IsNullOrWhiteSpace($line)){
                try{
                    $evt=$line|ConvertFrom-Json
                    # Ignore legacy/stale rows if an old file somehow survived a rotation.
                    if($evt.sessionId -and ([string]$evt.sessionId -ne [string]$script:sessionId)){continue}
                    [void]$rows.Add($evt)
                    if($evt.recordedAt){$last=[string]$evt.recordedAt}
                }catch{}
            }
        }
        $base.hasSession=($rows.Count -gt 0)
        $base.events=@($rows)
        $base.savedAt=$last
        return [pscustomobject]$base
    }catch{
        return [pscustomobject]@{
            ok=$false
            sessionId=[string]$script:sessionId
            hasSession=$false
            events=@()
            savedAt=$null
            error=$_.Exception.Message
        }
    }
}
function Append-SessionEvent($evt,[string]$clientSessionId) {
    if(-not(Test-SessionIdentity $clientSessionId)){return Register-StaleSessionWrite $clientSessionId 1}
    if($null -eq $evt){throw "No session event supplied."}
    $evt | Add-Member -NotePropertyName sessionId -NotePropertyValue ([string]$script:sessionId) -Force
    $line=$evt|ConvertTo-Json -Depth 8 -Compress
    Add-Content -LiteralPath $sessionStatePath -Value $line -Encoding UTF8
    $historyCount=Append-LootHistoryEvents @($evt)
    return [pscustomobject]@{ok=$true;count=1;historyCount=$historyCount;sessionId=[string]$script:sessionId;path=$sessionStatePath}
}
function Append-SessionEvents($items,[string]$clientSessionId) {
    $batch=@($items)
    if(-not(Test-SessionIdentity $clientSessionId)){return Register-StaleSessionWrite $clientSessionId $batch.Count}
    if($batch.Count -eq 0){return [pscustomobject]@{ok=$true;count=0;sessionId=[string]$script:sessionId;path=$sessionStatePath}}
    $lines=New-Object System.Collections.Generic.List[string]
    foreach($evt in $batch){
        if($null -eq $evt){continue}
        $evt | Add-Member -NotePropertyName sessionId -NotePropertyValue ([string]$script:sessionId) -Force
        $lines.Add(($evt|ConvertTo-Json -Depth 8 -Compress))
    }
    if($lines.Count -gt 0){Add-Content -LiteralPath $sessionStatePath -Value $lines.ToArray() -Encoding UTF8}
    $historyCount=Append-LootHistoryEvents $batch
    return [pscustomobject]@{ok=$true;count=$lines.Count;historyCount=$historyCount;sessionId=[string]$script:sessionId;path=$sessionStatePath}
}
function Clear-SessionState([string]$clientSessionId) {
    if(-not(Test-SessionIdentity $clientSessionId)){return Register-StaleSessionWrite $clientSessionId 0}
    $closedSessionId=[string]$script:sessionId

    # Rotate first. Delayed writes for the closed session are invalid from here on.
    $newSessionId=Rotate-SessionIdentity

    # Establish an authoritative source boundary at the current end of the EQ log.
    # Anything already in the file belongs to the closed session and must never
    # be emitted again as a new event, even if StreamReader/file buffering behaved
    # unexpectedly on an earlier read.
    $oldPosition=[int64]$position
    $sourceEnd=[int64]$position
    try{
        $sourceInfo=Get-Item -LiteralPath $logPath -ErrorAction Stop
        $sourceEnd=[int64]$sourceInfo.Length
    }catch{}
    $position=$sourceEnd
    $carry=""
    $script:sessionStartPosition=$sourceEnd
    $script:sessionResetAt=(Get-Date).ToString("o")

    if(Test-Path -LiteralPath $sessionStatePath){Remove-Item -LiteralPath $sessionStatePath -Force}
    $clearedBufferedEvents=$events.Count
    $events.Clear()

    return [pscustomobject]@{
        ok=$true
        closedSessionId=$closedSessionId
        sessionId=$newSessionId
        sessionCreatedAt=[string]$script:sessionCreatedAt
        clearedBufferedEvents=$clearedBufferedEvents
        nextEventId=$nextId
        previousLogPosition=$oldPosition
        sessionStartPosition=$script:sessionStartPosition
        logLengthAtReset=$sourceEnd
        sessionResetAt=$script:sessionResetAt
        staleSessionRejects=[int]$script:staleSessionRejects
    }
}

Start-HistoryIndexWorker
Start-PersistenceWorker
Start-LiveEventWorker

$shutdownForUpdate=$false
$listener=New-Object Net.HttpListener;$prefix="http://127.0.0.1:$port/";$listener.Prefixes.Add($prefix);$listener.Start()
Write-Host "";Write-Host "EverQuest Research & Loot Tool v0.17.1-demo.1";Write-Host "Open:     $prefix";Write-Host "";Write-Host "Keep this window open while playing. Press Ctrl+C to stop.";Write-Host ""

try{
while($listener.IsListening){
    $task=$listener.GetContextAsync()
    while(-not$task.Wait(250)){}
    $ctx=$task.Result;$req=$ctx.Request;$res=$ctx.Response
    $res.Headers["Access-Control-Allow-Origin"]="*"
    $res.Headers["Access-Control-Allow-Methods"]="GET, POST, OPTIONS"
    $res.Headers["Access-Control-Allow-Headers"]="Content-Type"
    if($req.HttpMethod -eq "OPTIONS"){$res.StatusCode=204;$res.OutputStream.Close();continue}
    try{
        $path=$req.Url.AbsolutePath


        if($path -eq "/api/session-state"){
            try{$payload=(Get-SessionState|ConvertTo-Json -Depth 12)}catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/session-event"){
            try{
                $body=Read-RequestJson $req
                $result=Append-SessionEvent $body.event ([string]$body.sessionId)
                if($result.staleSession){$res.StatusCode=409}
                $payload=($result|ConvertTo-Json -Depth 6)
            }catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/session-events"){
            try{
                $body=Read-RequestJson $req
                $items=@()
                if($body -and $body.events){$items=@($body.events)}
                $result=Append-SessionEvents $items ([string]$body.sessionId)
                if($result.staleSession){$res.StatusCode=409}
                $payload=($result|ConvertTo-Json -Depth 6)
            }catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/session-clear"){
            try{
                $body=Read-RequestJson $req
                $result=Clear-SessionState ([string]$body.sessionId)
                if($result.staleSession){$res.StatusCode=409}
                $payload=($result|ConvertTo-Json -Depth 6)
            }catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }

        if($path -eq "/api/loot-history-summary"){
            try{
                $index=Get-HistoryIndex
                $archiveCount=@(Get-ChildItem -LiteralPath $lootHistoryRoot -Filter "loot-history-????-??.jsonl" -File -ErrorAction SilentlyContinue).Count
                $payload=[pscustomobject]@{
                    ok=$true
                    enabled=($config.observedLootHistoryEnabled -ne $false)
                    totalEvents=[int64]$index.totalEvents
                    totalItems=@($index.items.PSObject.Properties).Count
                    totalZones=@($index.zones.PSObject.Properties).Count
                    totalLooters=@($index.looters.PSObject.Properties).Count
                    totalBytes=[int64]$index.totalBytes
                    archiveCount=$archiveCount
                    oldest=$index.oldest
                    newest=$index.newest
                }|ConvertTo-Json -Depth 6
            }catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/loot-history"){
            try{
                $limit=5000
                [void][int]::TryParse($req.QueryString["limit"],[ref]$limit)
                $item=[string]$req.QueryString["item"]
                $zone=[string]$req.QueryString["zone"]
                $looter=[string]$req.QueryString["looter"]
                $value=[string]$req.QueryString["value"]
                $payload=(Get-LootHistory $limit $item $zone $looter $value|ConvertTo-Json -Depth 12)
            }catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/loot-history-setting"){
            try{
                if($req.HttpMethod -eq "POST"){
                    $body=Read-RequestJson $req
                    $config.observedLootHistoryEnabled=[bool]$body.enabled
                    Save-Config $config
                }
                $payload=[pscustomobject]@{ok=$true;enabled=($config.observedLootHistoryEnabled -ne $false)}|ConvertTo-Json
            }catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/loot-history-rebuild-index"){
            try{$payload=[pscustomobject]@{ok=$true;index=(Rebuild-HistoryIndex)}|ConvertTo-Json -Depth 20}
            catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }

        if($path -eq "/api/update-state"){
            try{$payload=(Get-UpdateState | ConvertTo-Json -Depth 8)}
            catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/update-check"){
            try{$payload=(Get-UpdateInfo | ConvertTo-Json -Depth 8)}
            catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/update-download"){
            try{$payload=(Download-AndVerifyLatestUpdate | ConvertTo-Json -Depth 8)}
            catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/update-install"){
            try{$result=Start-SafeVerifiedUpdate;$payload=($result|ConvertTo-Json -Depth 8);$shutdownForUpdate=$true}
            catch{$payload=([pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json);$res.StatusCode=500}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);$res.OutputStream.Close()
            if($shutdownForUpdate){Start-Sleep -Milliseconds 750;$listener.Stop();break}
            continue
        }

        if($path -eq "/api/live-poll"){
            try{
                # Read the EQ log immediately when the browser asks for live data.
                # This keeps recognition independent from unrelated API requests.
                Read-NewLoot
                $since=0
                [void][int]::TryParse($req.QueryString["since"],[ref]$since)
                $selected=@($events|Where-Object{$_.id -gt $since})
                $appVersion=Get-AppVersionInfo
                $payload=[pscustomobject]@{
                    ok=$true
                    version=[string]$appVersion.version
                    channel=[string]$appVersion.channel
                    logPath=$logPath
                    logFile=$logFileName
                    character=$character
                    lastEventId=$nextId-1
                    position=$position
                    sessionStartPosition=$script:sessionStartPosition
                    sessionResetAt=$script:sessionResetAt
                    sessionId=[string]$script:sessionId
                    currentZone=$script:currentZone
                    currentZoneId=$script:currentZoneId
                    currentInstanceId=$script:currentInstanceId
                    currentZoneVersion=$script:currentZoneVersion
                    currentZoneEnteredAt=$script:currentZoneEnteredAt
                    observedLootHistoryEnabled=($config.observedLootHistoryEnabled -ne $false)
                    corpseRecoveryPending=[bool]$script:corpseRecoveryPending
                    corpseRecoveryActive=[bool]$script:corpseRecoveryActive
                    corpseRecoveryFirstLootSeen=[bool]$script:corpseRecoveryFirstLootSeen
                    corpseRecoveryLastLootAt=$(if($script:corpseRecoveryLastLootAt){$script:corpseRecoveryLastLootAt.ToString("o")}else{$null})
                    staleSessionRejects=[int]$script:staleSessionRejects
                    events=$selected
                    serverTime=(Get-Date).ToString("o")
                }|ConvertTo-Json -Depth 8
                $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
                $res.ContentType="application/json; charset=utf-8"
                $res.StatusCode=200
                $res.ContentLength64=$bytes.Length
                $res.OutputStream.Write($bytes,0,$bytes.Length)
            }catch{
                $payload=[pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json
                $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
                $res.StatusCode=500
                $res.ContentType="application/json; charset=utf-8"
                $res.ContentLength64=$bytes.Length
                $res.OutputStream.Write($bytes,0,$bytes.Length)
            }
            continue
        }

        if($path -eq "/api/status"){
            $sync=$null;if(Test-Path $syncDataPath){try{$sync=Get-Content $syncDataPath -Raw|ConvertFrom-Json}catch{}}
            $appVersion=Get-AppVersionInfo
            $payload=[pscustomobject]@{app="EverQuest Research & Loot Tool";version=[string]$appVersion.version;channel=[string]$appVersion.channel;root=$root;active=$true;logPath=$logPath;logFile=$logFileName;character=$character;lastEventId=$nextId-1;position=$position;sessionStartPosition=$script:sessionStartPosition;sessionResetAt=$script:sessionResetAt;sessionId=[string]$script:sessionId;currentZone=$script:currentZone;currentZoneId=$script:currentZoneId;currentInstanceId=$script:currentInstanceId;currentZoneVersion=$script:currentZoneVersion;currentZoneEnteredAt=$script:currentZoneEnteredAt;observedLootHistoryEnabled=($config.observedLootHistoryEnabled -ne $false);staleSessionRejects=[int]$script:staleSessionRejects;sync=$(if($sync){[pscustomobject]@{syncedAt=$sync.syncedAt;recipeCount=@($sync.recipes).Count;errors=@($sync.errors).Count}}else{$null})}|ConvertTo-Json -Depth 8
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.StatusCode=200;$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/events"){
            $since=0;[void][int]::TryParse($req.QueryString["since"],[ref]$since);$selected=@($events|Where-Object{$_.id -gt $since})
            $payload=[pscustomobject]@{events=$selected;lastEventId=$nextId-1}|ConvertTo-Json -Depth 6
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.StatusCode=200;$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/change-log"){
            $picked=Choose-LogFile
            if($picked){
                $config.logPath=$picked;Save-Config $config
                $payload=[pscustomobject]@{ok=$true;logPath=$picked;restartRequired=$true}|ConvertTo-Json
            }else{$payload=[pscustomobject]@{ok=$false}|ConvertTo-Json}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/bastion-sync"){
            try{
                $statusPath=Join-Path $root "data\bastion-sync-status.json"
                $existing=$null
                if(Test-Path $statusPath){try{$existing=Get-Content $statusPath -Raw|ConvertFrom-Json}catch{}}
                if($existing -and $existing.state -eq "running"){
                    $payload=[pscustomobject]@{ok=$true;started=$false;alreadyRunning=$true}|ConvertTo-Json
                }else{
                    $syncScript=Join-Path $root "sync-bastion.ps1"
                    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$syncScript,"-Root",$root)
                    $payload=[pscustomobject]@{ok=$true;started=$true}|ConvertTo-Json
                }
            }catch{$payload=[pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/bastion-spell-metadata-sync"){
            $statusPath=Join-Path $root "data\bastion-spell-metadata-status.json"
            try{
                # If a prior job exists, clean it up once it is no longer running.
                if($script:metadataSyncJob){
                    $jobState=[string]$script:metadataSyncJob.State
                    if($jobState -eq "Running" -or $jobState -eq "NotStarted"){
                        $payload=[pscustomobject]@{
                            ok=$true
                            started=$false
                            alreadyRunning=$true
                            jobId=$script:metadataSyncJob.Id
                        } | ConvertTo-Json
                        $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
                        $res.ContentType="application/json; charset=utf-8"
                        $res.ContentLength64=$bytes.Length
                        $res.OutputStream.Write($bytes,0,$bytes.Length)
                        continue
                    }else{
                        try{Remove-Job -Job $script:metadataSyncJob -Force -ErrorAction SilentlyContinue}catch{}
                        $script:metadataSyncJob=$null
                    }
                }

                $syncScript=Join-Path $root "sync-bastion-spell-metadata.ps1"
                if(-not(Test-Path -LiteralPath $syncScript)){
                    throw "Metadata sync script was not found: $syncScript"
                }

                [pscustomobject]@{
                    state="starting"
                    message="Starting Bastion spell metadata sync..."
                    pagesScanned=0
                    targetSpells=0
                    matchedNames=0
                    parsedSpells=0
                    errors=0
                    updatedAt=(Get-Date).ToString("o")
                } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statusPath -Encoding UTF8

                # Use a native Windows PowerShell background job.
                # This avoids all external powershell.exe path/quoting issues.
                $script:metadataSyncJob=Start-Job -FilePath $syncScript -ArgumentList $root

                if(-not $script:metadataSyncJob){
                    throw "PowerShell could not create the metadata background job."
                }

                $payload=[pscustomobject]@{
                    ok=$true
                    started=$true
                    jobId=$script:metadataSyncJob.Id
                    state=[string]$script:metadataSyncJob.State
                } | ConvertTo-Json
            }catch{
                $message=$_.Exception.Message
                try{
                    [pscustomobject]@{
                        state="error"
                        message="Could not start metadata sync: $message"
                        pagesScanned=0
                        targetSpells=0
                        matchedNames=0
                        parsedSpells=0
                        errors=1
                        updatedAt=(Get-Date).ToString("o")
                    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statusPath -Encoding UTF8
                }catch{}
                $payload=[pscustomobject]@{ok=$false;error=$message}|ConvertTo-Json
            }

            $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
            $res.ContentType="application/json; charset=utf-8"
            $res.ContentLength64=$bytes.Length
            $res.OutputStream.Write($bytes,0,$bytes.Length)
            continue
        }

        if($path -eq "/api/bastion-spell-metadata-diagnostics"){
            $jobState=""
            $jobId=$null
            $stdout=""
            $stderr=""
            if($script:metadataSyncJob){
                $jobState=[string]$script:metadataSyncJob.State
                $jobId=$script:metadataSyncJob.Id

                try{
                    $out=@(Receive-Job -Job $script:metadataSyncJob -Keep -ErrorAction SilentlyContinue)
                    if($out.Count -gt 0){$stdout=($out | Out-String)}
                }catch{}

                try{
                    $errs=@($script:metadataSyncJob.ChildJobs | ForEach-Object {$_.Error})
                    if($errs.Count -gt 0){$stderr=($errs | Out-String)}
                }catch{}

                try{
                    if(-not $stderr -and $script:metadataSyncJob.ChildJobs){
                        $reason=$script:metadataSyncJob.ChildJobs[0].JobStateInfo.Reason
                        if($reason){$stderr=[string]$reason}
                    }
                }catch{}
            }

            $payload=[pscustomobject]@{
                jobId=$jobId
                jobState=$jobState
                stdout=$stdout
                stderr=$stderr
            } | ConvertTo-Json -Depth 6

            $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
            $res.ContentType="application/json; charset=utf-8"
            $res.ContentLength64=$bytes.Length
            $res.OutputStream.Write($bytes,0,$bytes.Length)
            continue
        }

        if($path -eq "/api/bastion-spell-metadata-status"){
            $statusPath=Join-Path $root "data\bastion-spell-metadata-status.json"
            $statusObj=$null
            if(Test-Path $statusPath){
                try{$statusObj=Get-Content $statusPath -Raw|ConvertFrom-Json}catch{}
            }

            if(-not $statusObj){
                $statusObj=[pscustomobject]@{
                    state="idle";message="No spell metadata sync has been started.";
                    pagesScanned=0;targetSpells=0;matchedNames=0;parsedSpells=0;errors=0
                }
            }

            if($script:metadataSyncJob -and ($statusObj.state -eq "starting")){
                $js=[string]$script:metadataSyncJob.State
                if($js -eq "Failed"){
                    $reason=""
                    try{
                        $errs=@($script:metadataSyncJob.ChildJobs | ForEach-Object {$_.Error})
                        if($errs.Count -gt 0){$reason=($errs|Out-String).Trim()}
                        if(-not $reason){
                            $rr=$script:metadataSyncJob.ChildJobs[0].JobStateInfo.Reason
                            if($rr){$reason=[string]$rr}
                        }
                    }catch{}
                    if(-not $reason){$reason="Metadata PowerShell job failed before reporting progress."}
                    $statusObj.state="error"
                    $statusObj.message=$reason
                    $statusObj.errors=1
                }elseif($js -eq "Completed"){
                    # If the script completed without writing a complete/error state, flag it clearly.
                    $statusObj.state="error"
                    $statusObj.message="Metadata PowerShell job completed without producing a final sync status."
                    $statusObj.errors=1
                }
            }

            $payload=$statusObj|ConvertTo-Json -Depth 8
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
            $res.ContentType="application/json; charset=utf-8"
            $res.ContentLength64=$bytes.Length
            $res.OutputStream.Write($bytes,0,$bytes.Length)
            continue
        }
        if($path -eq "/api/bastion-spell-metadata"){
            $metadataPath=Join-Path $root "data\bastion-spell-metadata.json"
            if(Test-Path $metadataPath){$payload=Get-Content $metadataPath -Raw}else{$payload='{"version":"none","spells":[],"unresolved":[]}'}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/bastion-sync-status"){
            $statusPath=Join-Path $root "data\bastion-sync-status.json"
            if(Test-Path $statusPath){$payload=Get-Content $statusPath -Raw}else{$payload='{"state":"idle","message":"No sync has been started."}'}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/bastion-data"){
            if(Test-Path $syncDataPath){$payload=Get-Content $syncDataPath -Raw}else{$payload='{"version":"none","recipes":[]}'}
            $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length);continue
        }
        if($path -eq "/api/replay-test"){
            try{
                $lines=New-Object System.Collections.Generic.List[string]
                $fs=New-Object IO.FileStream($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                try{$sr=New-Object IO.StreamReader($fs);try{while(-not $sr.EndOfStream){$ln=$sr.ReadLine();$lines.Add($ln);if($lines.Count -gt 5000){$lines.RemoveAt(0)}}}finally{$sr.Dispose()}}finally{$fs.Dispose()}
                $all=New-Object System.Collections.ArrayList
                foreach($ln in $lines){$evt=Parse-LootLine $ln;if($evt){[void]$all.Add($evt)}}
                $payload=[pscustomobject]@{ok=$true;scannedLines=$lines.Count;lootEvents=@($all).Count;events=@($all|Select-Object -Last 150)}|ConvertTo-Json -Depth 8
                $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length)
            }catch{
                $payload=[pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json
                $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.StatusCode=500;$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length)
            }
            continue
        }


        if($path -eq "/api/magelo"){
            try{
                $requested=Normalize-MageloCharacter $req.QueryString["character"]
                if(-not $requested){throw "No Magelo character specified."}
                $url="https://characters.bastiongame.com/character/$requested"
                $html=Invoke-Bastion $url
                $parsed=Parse-MageloInventory $html $requested
                $payload=[pscustomobject]@{ok=$true;data=$parsed}|ConvertTo-Json -Depth 10
                $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length)
            }catch{
                $payload=[pscustomobject]@{ok=$false;error=$_.Exception.Message}|ConvertTo-Json
                $bytes=[Text.Encoding]::UTF8.GetBytes($payload);$res.StatusCode=500;$res.ContentType="application/json; charset=utf-8";$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length)
            }
            continue
        }
        $relative=$path.TrimStart("/");if(-not$relative){$relative="index.html"};$relative=$relative.Replace("/",[IO.Path]::DirectorySeparatorChar)
        $target=[IO.Path]::GetFullPath((Join-Path $root $relative));$rootFull=[IO.Path]::GetFullPath($root)
        if(-not$target.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){$res.StatusCode=403;continue}
        if(-not(Test-Path -LiteralPath $target -PathType Leaf)){$res.StatusCode=404;continue}
        $bytes=[IO.File]::ReadAllBytes($target)
        $ext=[IO.Path]::GetExtension($target).ToLowerInvariant()
        if($ext -eq ".png" -or $ext -eq ".jpg" -or $ext -eq ".jpeg" -or $ext -eq ".gif" -or $ext -eq ".ico"){
            # Immutable local artwork can be cached; these files do not change in-place within a build.
            $res.Headers["Cache-Control"]="public, max-age=86400"
        }else{
            # App shell/code/data must never survive across an installed build change.
            $res.Headers["Cache-Control"]="no-store, no-cache, must-revalidate, max-age=0"
            $res.Headers["Pragma"]="no-cache"
            $res.Headers["Expires"]="0"
        }
        $res.ContentType=Get-ContentType $target
        $res.ContentLength64=$bytes.Length
        $res.OutputStream.Write($bytes,0,$bytes.Length)
    }catch{
        try{$msg=[Text.Encoding]::UTF8.GetBytes($_.Exception.Message);$res.StatusCode=500;$res.ContentType="text/plain; charset=utf-8";$res.ContentLength64=$msg.Length;$res.OutputStream.Write($msg,0,$msg.Length)}catch{}
    }finally{try{$res.OutputStream.Close()}catch{}}
}
 }finally{
    try{
        if($script:historyIndexWorkerProcess -and -not $script:historyIndexWorkerProcess.HasExited){
            Stop-Process -Id $script:historyIndexWorkerProcess.Id -Force -ErrorAction SilentlyContinue
        }
        if($script:persistenceWorkerProcess -and -not $script:persistenceWorkerProcess.HasExited){
            Stop-Process -Id $script:persistenceWorkerProcess.Id -Force -ErrorAction SilentlyContinue
        }
        if($script:liveEventWorkerProcess -and -not $script:liveEventWorkerProcess.HasExited){
            Stop-Process -Id $script:liveEventWorkerProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }catch{}
    try{$listener.Stop()}catch{}
    try{$listener.Close()}catch{}
}
