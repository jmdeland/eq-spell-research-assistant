param([string]$LogPath = "")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $root "monitor-config.json"
$syncDataPath = Join-Path $root "data\bastion-synced-recipes.json"

function Get-Config {
    if (Test-Path $configPath) {
        try { return (Get-Content $configPath -Raw | ConvertFrom-Json) } catch {}
    }
    return [pscustomobject]@{
        logPath = ""
        port = 8765
        startAtEnd = $true
    }
}
function Save-Config($cfg) {$cfg | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8}
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
    return (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 45 -Headers @{"User-Agent"="EQ-Spell-Research-Assistant/0.12"}).Content
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
    $payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $syncDataPath -Encoding UTF8
    return $payload
}

$config=Get-Config
if($LogPath){$config.logPath=$LogPath}
if(-not $config.port){$config | Add-Member -NotePropertyName port -NotePropertyValue 8765 -Force}
if($null -eq $config.startAtEnd){$config | Add-Member -NotePropertyName startAtEnd -NotePropertyValue $true -Force}
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

$events=New-Object System.Collections.ArrayList
$nextId=1
$position=0L
$carry=""
$script:metadataSyncJob=$null
try{$fi=Get-Item -LiteralPath $logPath;if($config.startAtEnd -ne $false){$position=[int64]$fi.Length}}catch{}


function Parse-LootLine([string]$line) {
    if(-not $line){return $null}
    $m=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*--You have looted (?:a|an) (?<item>.+?)\.--\s*$')
    if($m.Success){
        return [pscustomobject]@{timestamp=$m.Groups['time'].Value;looter=$(if($character){$character}else{"You"});self=$true;item=$m.Groups['item'].Value;raw=$line}
    }
    $m=[regex]::Match($line,'^\[(?<time>[^\]]+)\]\s*--(?<looter>.+?) has looted (?:a|an) (?<item>.+?)\.--\s*$')
    if($m.Success){
        $l=$m.Groups['looter'].Value
        return [pscustomobject]@{timestamp=$m.Groups['time'].Value;looter=$l;self=$(if($character -and $l -eq $character){$true}else{$false});item=$m.Groups['item'].Value;raw=$line}
    }
    return $null
}
function Read-NewLoot {
    if(-not $logPath -or -not(Test-Path -LiteralPath $logPath)){return}
    $fi=Get-Item -LiteralPath $logPath
    if($fi.Length -lt $position){$position=0L;$carry=""}
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
        $evt=Parse-LootLine $line
        if($evt){$evt|Add-Member -NotePropertyName id -NotePropertyValue $nextId -Force;[void]$events.Add($evt);$nextId++}
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

        [void]$items.Add([pscustomobject]@{
            source="Magelo"
            character=$characterName
            location=$location
            rawLocation=$loc
            name=[string]$x.name
            id=[int]$x.id
            count=1
            bagSlot=$x.bagSlot
            parentId=$x.parentId
        })
    }

    # Bastion emits one row per actual item instance/slot.
    # Aggregate exact item IDs within each location to get quantity.
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
        $agg[$key].count++
    }

    return [pscustomobject]@{
        character=$characterName
        url="https://characters.bastiongame.com/character/$characterName"
        bankHidden=$bankHidden
        items=@($agg.Values)
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

$listener=New-Object Net.HttpListener;$prefix="http://127.0.0.1:$port/";$listener.Prefixes.Add($prefix);$listener.Start()
Write-Host "";Write-Host "EverQuest Spell Research Assistant v0.14.0";Write-Host "Open:     $prefix";Write-Host "";Write-Host "Keep this window open while playing. Press Ctrl+C to stop.";Write-Host ""
Start-Process ($prefix + "index.html")

try{
while($listener.IsListening){
    Read-NewLoot
    $task=$listener.GetContextAsync()
    while(-not$task.Wait(250)){Read-NewLoot}
    $ctx=$task.Result;$req=$ctx.Request;$res=$ctx.Response
    $res.Headers["Access-Control-Allow-Origin"]="*"
    $res.Headers["Access-Control-Allow-Methods"]="GET, OPTIONS"
    $res.Headers["Access-Control-Allow-Headers"]="Content-Type"
    if($req.HttpMethod -eq "OPTIONS"){$res.StatusCode=204;$res.OutputStream.Close();continue}
    try{
        $path=$req.Url.AbsolutePath

        if($path -eq "/api/status"){
            $sync=$null;if(Test-Path $syncDataPath){try{$sync=Get-Content $syncDataPath -Raw|ConvertFrom-Json}catch{}}
            $payload=[pscustomobject]@{active=$true;logPath=$logPath;logFile=$logFileName;character=$character;lastEventId=$nextId-1;position=$position;sync=$(if($sync){[pscustomobject]@{syncedAt=$sync.syncedAt;recipeCount=@($sync.recipes).Count;errors=@($sync.errors).Count}}else{$null})}|ConvertTo-Json -Depth 8
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
        $bytes=[IO.File]::ReadAllBytes($target);$res.ContentType=Get-ContentType $target;$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length)
    }catch{
        try{$msg=[Text.Encoding]::UTF8.GetBytes($_.Exception.Message);$res.StatusCode=500;$res.ContentType="text/plain; charset=utf-8";$res.ContentLength64=$msg.Length;$res.OutputStream.Write($msg,0,$msg.Length)}catch{}
    }finally{try{$res.OutputStream.Close()}catch{}}
}
}finally{try{$listener.Stop()}catch{};try{$listener.Close()}catch{}}
