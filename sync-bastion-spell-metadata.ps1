param(
    [string]$Root = ""
)

$ErrorActionPreference="Stop"
if(-not $Root){$Root=Split-Path -Parent $MyInvocation.MyCommand.Path}

$outPath=Join-Path $Root "data\bastion-spell-metadata.json"
$statusPath=Join-Path $Root "data\bastion-spell-metadata-status.json"

function Write-Status($state,$message,$pages=0,$targets=0,$matched=0,$parsed=0,$errors=0){
    [pscustomobject]@{
        state=$state
        message=$message
        pagesScanned=$pages
        targetSpells=$targets
        matchedNames=$matched
        parsedSpells=$parsed
        errors=$errors
        updatedAt=(Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}

function Strip-Html([string]$html){
    $x=[regex]::Replace($html,'<script\b[^>]*>.*?</script>',' ','Singleline,IgnoreCase')
    $x=[regex]::Replace($x,'<style\b[^>]*>.*?</style>',' ','Singleline,IgnoreCase')
    $x=[regex]::Replace($x,'<[^>]+>',' ')
    $x=[Net.WebUtility]::HtmlDecode($x)
    return ([regex]::Replace($x,'\s+',' ')).Trim()
}

function Normalize-SpellName([string]$name){
    if($null -eq $name){return ""}
    $n=[Net.WebUtility]::HtmlDecode([string]$name).Trim().ToLowerInvariant()
    $n=$n -replace '^spell:\s*',''
    $n=$n.Replace([char]0x2019,"'").Replace([char]0x2018,"'").Replace([char]0x60,"'")
    $n=[regex]::Replace($n,'\s+',' ')
    return $n.Trim()
}

function Invoke-Bastion([string]$url){
    return (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 45 -Headers @{"User-Agent"="EQ-Spell-Research-Assistant/0.14.0"}).Content
}

$classMap=@{
    "Warrior"="WAR";"Cleric"="CLR";"Paladin"="PAL";"Ranger"="RNG";
    "Shadow Knight"="SHD";"Shadowknight"="SHD";"Druid"="DRU";"Monk"="MNK";
    "Bard"="BRD";"Rogue"="ROG";"Shaman"="SHM";"Necromancer"="NEC";
    "Wizard"="WIZ";"Magician"="MAG";"Enchanter"="ENC";"Beastlord"="BST";
    "Berserker"="BER"
}

function Parse-SpellPage([int]$spellId,[string]$expectedName,[string]$html){
    $plain=Strip-Html $html

    $body=""
    $m=[regex]::Match($plain,'\bClasses\b\s*(?<body>.*?)\s*\bLearned from\b','IgnoreCase')
    if($m.Success){$body=$m.Groups['body'].Value.Trim()}

    if(-not $body){
        return [pscustomobject]@{
            name=$expectedName;spellId=$spellId;classes=@();levelByClass=[pscustomobject]@{};
            sourceUrl="https://library.bastiongame.com/spells/$spellId";
            complete=$false;parseWarning="Classes section not found."
        }
    }

    $pairs=New-Object -TypeName 'System.Collections.ArrayList'
    $pattern='(?<class>Shadow Knight|Shadowknight|Necromancer|Enchanter|Beastlord|Berserker|Magician|Warrior|Cleric|Paladin|Ranger|Druid|Monk|Bard|Rogue|Shaman|Wizard)\s*\((?<level>\d+)\)'
    foreach($cm in [regex]::Matches($body,$pattern,'IgnoreCase')){
        $full=(Get-Culture).TextInfo.ToTitleCase($cm.Groups['class'].Value.ToLowerInvariant())
        if($full -eq "Shadowknight"){$full="Shadowknight"}
        $abbr=$classMap[$full]
        if(-not $abbr){
            # Case-insensitive fallback through keys
            foreach($k in $classMap.Keys){if($k -ieq $cm.Groups['class'].Value){$abbr=$classMap[$k];break}}
        }
        if($abbr){
            [void]$pairs.Add([pscustomobject]@{abbr=$abbr;level=[int]$cm.Groups['level'].Value})
        }
    }

    $levels=[ordered]@{}
    foreach($p in $pairs){$levels[$p.abbr]=$p.level}
    $classes=@($levels.Keys)

    return [pscustomobject]@{
        name=$expectedName
        spellId=$spellId
        classes=$classes
        levelByClass=[pscustomobject]$levels
        sourceUrl="https://library.bastiongame.com/spells/$spellId"
        complete=($classes.Count -gt 0)
        parseWarning=$(if($classes.Count -gt 0){$null}else{"No class/level pairs parsed from Classes section: $body"})
    }
}

try{
    Write-Status "running" "Collecting Research spell names..."

    $targets=New-Object -TypeName 'System.Collections.Generic.Dictionary[string,string]'

    foreach($fileName in @("bastion-synced-recipes.json","bastion-recipes.json")){
        $path=Join-Path $Root "data\$fileName"
        if(-not(Test-Path -LiteralPath $path)){continue}
        try{
            $data=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $rows=$(if($data.recipes){@($data.recipes)}else{@($data)})
            foreach($r in $rows){
                $isSpell=$false
                if($null -ne $r.isSpellRecipe){$isSpell=[bool]$r.isSpellRecipe}
                elseif([string]$r.recipeName -match '^Spell:\s*'){$isSpell=$true}
                if(-not $isSpell){continue}
                $name=[string]$r.spell
                if(-not $name){$name=([string]$r.recipeName -replace '^Spell:\s*','').Trim()}
                $key=Normalize-SpellName $name
                if($key -and -not $targets.ContainsKey($key)){$targets.Add($key,$name)}
            }
        }catch{}
    }

    if($targets.Count -eq 0){throw "No Research spell names were found in the packaged Bastion recipe data."}

    Write-Status "running" "Resolving Research spell names through Bastion spell search..." 0 $targets.Count 0 0 0

    # Bastion /spells is search-driven, not an unfiltered browse index.
    # Resolve each Research spell name through ?name=<exact spell name>.
    $index=@{}
    $resolved=0
    $searchNumber=0

    foreach($key in ($targets.Keys | Sort-Object)){
        $searchNumber++
        $desired=$targets[$key]
        Write-Status "running" ("Resolving spell name {0} of {1}: {2}" -f $searchNumber,$targets.Count,$desired) $searchNumber $targets.Count $resolved 0 0

        try{
            $encoded=[Uri]::EscapeDataString($desired)
            $searchUrl="https://library.bastiongame.com/spells?name=$encoded"
            $html=Invoke-Bastion $searchUrl

            # Result pages may contain several spell links. Accept only an exact normalized name match.
            $matches=[regex]::Matches(
                $html,
                'href=["''](?:https?://[^/"'']+)?/spells/(?<id>\d+)(?:[?"''#][^"'']*)?["''][^>]*>(?<name>.*?)</a>',
                'Singleline,IgnoreCase'
            )

            foreach($sm in $matches){
                $id=[int]$sm.Groups['id'].Value
                $name=Strip-Html $sm.Groups['name'].Value
                $candidate=Normalize-SpellName $name
                if($candidate -eq $key){
                    $index[$key]=[pscustomobject]@{
                        id=$id
                        name=$name
                        searchUrl=$searchUrl
                    }
                    $resolved++
                    break
                }
            }

            # Some result cards nest text/icons oddly. If exact anchor text did not match,
            # use a conservative fallback: if the page contains exactly one distinct spell ID
            # and the visible page text contains the exact requested name, accept that ID.
            if(-not $index.ContainsKey($key)){
                $ids=@(
                    [regex]::Matches($html,'href=["''][^"'']*/spells/(?<id>\d+)','IgnoreCase') |
                    ForEach-Object {[int]$_.Groups['id'].Value} |
                    Select-Object -Unique
                )
                $plain=Strip-Html $html
                if($ids.Count -eq 1 -and $plain -match [regex]::Escape($desired)){
                    $index[$key]=[pscustomobject]@{
                        id=$ids[0]
                        name=$desired
                        searchUrl=$searchUrl
                    }
                    $resolved++
                }
            }

        }catch{
            # Search failures become unresolved later rather than fabricating metadata.
        }

        Start-Sleep -Milliseconds 90
    }

    $spells=New-Object -TypeName 'System.Collections.ArrayList'
    $errs=New-Object -TypeName 'System.Collections.ArrayList'
    $unresolved=New-Object -TypeName 'System.Collections.ArrayList'
    $n=0

    foreach($key in ($targets.Keys|Sort-Object)){
        $desired=$targets[$key]
        if(-not $index.ContainsKey($key)){
            [void]$unresolved.Add([pscustomobject]@{name=$desired;reason="No exact normalized name match found in Bastion spell index."})
            continue
        }

        $n++
        $hit=$index[$key]
        Write-Status "running" ("Fetching spell metadata {0} of {1}: {2}" -f $n,$index.Count,$desired) $searchNumber $targets.Count $index.Count $spells.Count $errs.Count
        try{
            $r=Parse-SpellPage $hit.id $desired (Invoke-Bastion "https://library.bastiongame.com/spells/$($hit.id)")
            if($r.complete){[void]$spells.Add($r)}
            else{
                [void]$errs.Add(("Spell {0} {1}: {2}" -f $hit.id,$desired,$r.parseWarning))
                [void]$unresolved.Add([pscustomobject]@{name=$desired;spellId=$hit.id;reason=$r.parseWarning;sourceUrl=$r.sourceUrl})
            }
        }catch{
            [void]$errs.Add(("Spell {0} {1}: {2}" -f $hit.id,$desired,$_.Exception.Message))
            [void]$unresolved.Add([pscustomobject]@{name=$desired;spellId=$hit.id;reason=$_.Exception.Message;sourceUrl="https://library.bastiongame.com/spells/$($hit.id)"})
        }

        if(($n%20)-eq 0){Start-Sleep -Milliseconds 120}
    }

    $payload=[pscustomobject]@{
        version="0.14.0-metadata"
        syncedAt=(Get-Date).ToString("o")
        source="https://library.bastiongame.com/spells"
        targetCount=$targets.Count
        searchesCompleted=$searchNumber
        matchedNames=$index.Count
        spells=@($spells)
        unresolved=@($unresolved)
        errors=@($errs)
    }

    $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Status "complete" "Bastion spell metadata sync complete." $searchNumber $targets.Count $index.Count $spells.Count $errs.Count
}catch{
    Write-Status "error" $_.Exception.Message
    exit 1
}
