param(
    [string]$Root = ""
)
$ErrorActionPreference="Stop"
if(-not $Root){$Root=Split-Path -Parent $MyInvocation.MyCommand.Path}
$outPath=Join-Path $Root "data\bastion-synced-recipes.json"
$statusPath=Join-Path $Root "data\bastion-sync-status.json"

function Write-Status($state,$message,$pages=0,$ids=0,$parsed=0,$errors=0){
    [pscustomobject]@{
        state=$state
        message=$message
        pagesScanned=$pages
        recipeIdsFound=$ids
        recipeCount=$parsed
        errors=$errors
        updatedAt=(Get-Date).ToString("o")
    }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $statusPath -Encoding UTF8
}
function Strip-Html([string]$html){
    $x=[regex]::Replace($html,'<script\b[^>]*>.*?</script>',' ','Singleline,IgnoreCase')
    $x=[regex]::Replace($x,'<style\b[^>]*>.*?</style>',' ','Singleline,IgnoreCase')
    $x=[regex]::Replace($x,'<[^>]+>',' ')
    $x=[Net.WebUtility]::HtmlDecode($x)
    return ([regex]::Replace($x,'\s+',' ')).Trim()
}
function Invoke-Bastion([string]$url){
    return (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 45 -Headers @{"User-Agent"="EQ-Spell-Research-Assistant/0.12.8"}).Content
}
function Parse-RecipePage([int]$id,[string]$html){
    $plain=Strip-Html $html
    $tm=[regex]::Match($plain,'Research\s*-\s*(?<t>\d+)\s+trivial','IgnoreCase')
    if(-not $tm.Success){return $null}
    $trivial=[int]$tm.Groups['t'].Value
    $name=""
    $nm=[regex]::Match($plain,'Recipe\s*-\s*(?<n>.+?)\s+Searches recipe by name','IgnoreCase')
    if($nm.Success){$name=$nm.Groups['n'].Value.Trim()}
    if(-not $name){
        $nm=[regex]::Match($plain,'Recipe\s+(?<n>.+?)\s+Research\s*-\s*\d+\s+trivial','IgnoreCase')
        if($nm.Success){$name=$nm.Groups['n'].Value.Trim()}
    }
    if(-not $name){$name="Recipe $id"}
    $name=[regex]::Replace($name,'^\s*-\s*','')
    $name=[regex]::Replace($name,'\s+Tradeskill\s+-.*$','', 'IgnoreCase')
    $isSpell=$name -match '^Spell:\s*'
    $spell=$name -replace '^Spell:\s*',''
    $spell=$spell.Trim()

    $ingHtml=$html
    $im=[regex]::Match($html,'Ingredients(?<body>.*?)Creates','Singleline,IgnoreCase')
    if($im.Success){$ingHtml=$im.Groups['body'].Value}
    $components=New-Object System.Collections.ArrayList

    # Linked items
    $matches=[regex]::Matches($ingHtml,'(?<qty>\d+)\s*x(?:(?!\d+\s*x).){0,700}?href=["''][^"'']*/items/(?<id>\d+)["''][^>]*>(?<name>.*?)</a>','Singleline,IgnoreCase')
    foreach($m in $matches){
        $n=Strip-Html $m.Groups['name'].Value
        if($n){
            $o=[ordered]@{name=$n;id=[int]$m.Groups['id'].Value}
            $q=[int]$m.Groups['qty'].Value;if($q -gt 1){$o.count=$q}
            if($n -eq "Quill" -or $n -eq "Piece of Parchment"){$o.vendorBasic=$true}
            [void]$components.Add([pscustomobject]$o)
        }
    }

    # Fallback plain-text ingredients when Bastion doesn't emit item links.
    $ingPlain=Strip-Html $ingHtml
    if($components.Count -eq 0){
        $chunks=[regex]::Matches($ingPlain,'(?<qty>\d+)\s*x\s+(?<name>.+?)(?=(?:\d+\s*x)|$)','IgnoreCase')
        foreach($m in $chunks){
            $n=$m.Groups['name'].Value
            $n=[regex]::Replace($n,'\s+(Bought|Dropped|Foraged|Crafted|Unknown)(?:,\s*[^,]+)*\s*$','', 'IgnoreCase').Trim()
            if($n){
                $o=[ordered]@{name=$n}
                $q=[int]$m.Groups['qty'].Value;if($q -gt 1){$o.count=$q}
                if($n -eq "Quill" -or $n -eq "Piece of Parchment"){$o.vendorBasic=$true}
                [void]$components.Add([pscustomobject]$o)
            }
        }
    }

    if($components.Count -eq 0){
        return [pscustomobject]@{
            recipeId=$id;recipeKey="bastion:$id";class="ALL";classes=@();level=$null;
            spell=$spell;recipeName=$name;isSpellRecipe=$isSpell;trivial=$trivial;components=@();
            source="Bastion synced";sourceUrl="https://library.bastiongame.com/recipes/$id";
            containers=@();verification="bastion-live-sync-partial";complete=$false;yield=1;
            parseWarning="Research recipe discovered, but Bastion did not expose ingredient identities in a form the parser could safely map."
        }
    }
    return [pscustomobject]@{
        recipeId=$id;recipeKey="bastion:$id";class="ALL";classes=@();level=$null;
        spell=$spell;recipeName=$name;isSpellRecipe=$isSpell;trivial=$trivial;components=@($components);
        source="Bastion synced";sourceUrl="https://library.bastiongame.com/recipes/$id";containers=@();
        verification="bastion-live-sync";complete=$true;yield=1
    }
}

try{
    Write-Status "running" "Starting Bastion Research discovery..."
    $ids=New-Object System.Collections.Generic.HashSet[int]
    $seen=New-Object System.Collections.Generic.HashSet[string]
    $page=1;$pages=0

    while($page -le 500){
        Write-Status "running" "Scanning Bastion recipe index page $page..." $pages $ids.Count 0 0
        $html=Invoke-Bastion "https://library.bastiongame.com/recipes?page=$page"
        $pages++
        $all=[regex]::Matches($html,'href=["''](?:https?://[^/"'']+)?/recipes/(?<id>\d+)(?:[?"''])','IgnoreCase')
        $allIds=@();foreach($m in $all){$allIds += [int]$m.Groups['id'].Value}
        $allIds=@($allIds|Select-Object -Unique)
        if($allIds.Count -eq 0){break}
        $sig=$allIds -join ","
        if(-not $seen.Add($sig)){break}

        $rows=[regex]::Matches($html,'<tr\b[^>]*>(?<row>.*?)</tr>','Singleline,IgnoreCase')
        foreach($rm in $rows){
            $rowHtml=$rm.Groups['row'].Value
            $rowText=Strip-Html $rowHtml
            if($rowText -notmatch '(?i)\bResearch\b'){continue}
            $idmatch=[regex]::Match($rowHtml,'href=["''](?:https?://[^/"'']+)?/recipes/(?<id>\d+)(?:[?"''])','IgnoreCase')
            if($idmatch.Success){[void]$ids.Add([int]$idmatch.Groups['id'].Value)}
        }
        $page++
        Start-Sleep -Milliseconds 75
    }

    $recipes=New-Object System.Collections.ArrayList
    $errs=New-Object System.Collections.ArrayList
    $n=0
    foreach($id in ($ids|Sort-Object)){
        $n++
        Write-Status "running" "Fetching Research recipe $n of $($ids.Count)..." $pages $ids.Count $recipes.Count $errs.Count
        try{
            $r=Parse-RecipePage $id (Invoke-Bastion "https://library.bastiongame.com/recipes/$id")
            if($r){[void]$recipes.Add($r)}else{[void]$errs.Add("Recipe $id did not parse")}
        }catch{[void]$errs.Add("Recipe ${id}: $($_.Exception.Message)")}
        if(($n%20)-eq 0){Start-Sleep -Milliseconds 120}
    }

    $payload=[pscustomobject]@{
        version="0.12.8-sync";syncedAt=(Get-Date).ToString("o");
        source="https://library.bastiongame.com/recipes";tradeskill="Research";
        discoveryMode="full-index-async";pagesScanned=$pages;recipeIdsFound=$ids.Count;
        recipes=@($recipes);errors=@($errs)
    }
    $payload|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $outPath -Encoding UTF8
    Write-Status "complete" "Bastion Research sync complete." $pages $ids.Count $recipes.Count $errs.Count
}catch{
    Write-Status "error" $_.Exception.Message
    exit 1
}
