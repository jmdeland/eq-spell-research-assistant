param(
    [Parameter(Mandatory=$true)][int]$ParentPid
)

$ErrorActionPreference="SilentlyContinue"
$userDataRoot=Join-Path $env:LOCALAPPDATA "EverQuest Research & Loot Tool"
$historyRoot=Join-Path $userDataRoot "history"
$indexPath=Join-Path $historyRoot "loot-history-index.json"
$statePath=Join-Path $historyRoot "history-index-worker-state.json"

if(-not(Test-Path -LiteralPath $historyRoot)){New-Item -ItemType Directory -Path $historyRoot -Force|Out-Null}

$mutex=New-Object Threading.Mutex($false,"EQResearchLootHistoryIndexWorker")
$hasMutex=$false
try{$hasMutex=$mutex.WaitOne(0)}catch{}
if(-not $hasMutex){exit 0}

function Write-AtomicUtf8File([string]$Path,[string]$Text){
    $dir=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp=Join-Path $dir (([IO.Path]::GetFileName($Path))+".tmp."+[guid]::NewGuid().ToString("N"))
    [IO.File]::WriteAllText($tmp,$Text,(New-Object Text.UTF8Encoding($false)))
    if(Test-Path -LiteralPath $Path){
        try{[IO.File]::Replace($tmp,$Path,$null,$true);return}catch{}
        try{Remove-Item -LiteralPath $Path -Force -ErrorAction Stop}catch{}
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Normalize-Key([string]$value){
    if($null -eq $value){return ""}
    return ([regex]::Replace($value.Trim().ToLowerInvariant(),'\s+',' '))
}
function Empty-Index {
    return [pscustomobject]@{
        schema=1;totalEvents=0;totalBytes=0;oldest=$null;newest=$null;
        months=[pscustomobject]@{};items=[pscustomobject]@{};zones=[pscustomobject]@{};looters=[pscustomobject]@{};
        updatedAt=$null
    }
}
function Ensure-Prop($obj,[string]$name,$value){
    if($null -eq $obj.PSObject.Properties[$name]){$obj|Add-Member -NotePropertyName $name -NotePropertyValue $value -Force}
    return $obj.PSObject.Properties[$name].Value
}
function Add-Month($obj,[string]$month){
    $arr=@()
    if($obj.PSObject.Properties["months"]){$arr=@($obj.months)}
    if($arr -notcontains $month){$obj|Add-Member -NotePropertyName months -NotePropertyValue @($arr+$month) -Force}
}
function Apply-Event($index,$evt,[string]$month,[int64]$lineBytes){
    if($null -eq $evt){return}
    $index.totalEvents=[int64]$index.totalEvents+1
    $index.totalBytes=[int64]$index.totalBytes+$lineBytes
    $when=[string]$(if($evt.timestamp){$evt.timestamp}else{$evt.recordedAt})
    if(-not $index.oldest){$index.oldest=$when}
    $index.newest=$when

    $mo=Ensure-Prop $index.months $month ([pscustomobject]@{count=0;bytes=0})
    $mo.count=[int64]$mo.count+1
    $mo.bytes=[int64]$mo.bytes+$lineBytes

    $ik=Normalize-Key ([string]$evt.item)
    if($ik){
        $io=Ensure-Prop $index.items $ik ([pscustomobject]@{name=[string]$evt.item;count=0;firstSeen=$when;lastSeen=$when;months=@()})
        $io.count=[int64]$io.count+1
        if(-not $io.firstSeen){$io.firstSeen=$when}
        $io.lastSeen=$when
        Add-Month $io $month
    }

    $zone=[string]$(if($evt.zone){$evt.zone}else{"Unknown"})
    $zk=Normalize-Key $zone
    $zo=Ensure-Prop $index.zones $zk ([pscustomobject]@{name=$zone;count=0;months=@()})
    $zo.count=[int64]$zo.count+1
    Add-Month $zo $month

    $looter=[string]$(if($evt.looter){$evt.looter}else{"Unknown"})
    $lk=Normalize-Key $looter
    $lo=Ensure-Prop $index.looters $lk ([pscustomobject]@{name=$looter;count=0;months=@()})
    $lo.count=[int64]$lo.count+1
    Add-Month $lo $month
}
function Load-State {
    if(Test-Path -LiteralPath $statePath){
        try{$s=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json;if($s){return $s}}catch{}
    }
    return $null
}
function Save-State($state){
    Write-AtomicUtf8File $statePath ($state|ConvertTo-Json -Depth 8)
}
function Rebuild-All {
    $index=Empty-Index
    $state=[pscustomobject]@{schema=1;files=[pscustomobject]@{};updatedAt=$null}
    foreach($file in @(Get-ChildItem -LiteralPath $historyRoot -Filter "loot-history-????-??.jsonl" -File|Sort-Object Name)){
        $month=$file.BaseName.Substring(13)
        $offset=0L
        $fs=New-Object IO.FileStream($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try{
            $sr=New-Object IO.StreamReader($fs)
            try{
                while(-not $sr.EndOfStream){
                    $line=$sr.ReadLine()
                    $after=[int64]$fs.Position
                    $lineBytes=[Math]::Max(1,$after-$offset)
                    $offset=$after
                    if([string]::IsNullOrWhiteSpace($line)){continue}
                    try{$evt=$line|ConvertFrom-Json;Apply-Event $index $evt $month $lineBytes}catch{}
                }
            }finally{$sr.Dispose()}
        }finally{$fs.Dispose()}
        $state.files|Add-Member -NotePropertyName $file.Name -NotePropertyValue $offset -Force
    }
    $index.updatedAt=(Get-Date).ToString("o")
    $state.updatedAt=$index.updatedAt
    Write-AtomicUtf8File $indexPath ($index|ConvertTo-Json -Depth 15)
    Save-State $state
    return @($index,$state)
}

$pair=$null
$state=Load-State
if(-not $state -or -not(Test-Path -LiteralPath $indexPath)){
    $pair=Rebuild-All
    $index=$pair[0];$state=$pair[1]
}else{
    try{$index=Get-Content -LiteralPath $indexPath -Raw|ConvertFrom-Json}catch{$index=$null}
    if(-not $index){
        $pair=Rebuild-All
        $index=$pair[0];$state=$pair[1]
    }
}

$dirty=$false
$lastWrite=Get-Date
try{
    while($true){
        if(-not(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){break}

        foreach($file in @(Get-ChildItem -LiteralPath $historyRoot -Filter "loot-history-????-??.jsonl" -File -ErrorAction SilentlyContinue|Sort-Object Name)){
            $month=$file.BaseName.Substring(13)
            $offset=0L
            if($state.files.PSObject.Properties[$file.Name]){$offset=[int64]$state.files.PSObject.Properties[$file.Name].Value}
            if($file.Length -lt $offset){$offset=0L}
            if($file.Length -le $offset){continue}

            $fs=New-Object IO.FileStream($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            try{
                [void]$fs.Seek($offset,[IO.SeekOrigin]::Begin)
                $sr=New-Object IO.StreamReader($fs)
                try{
                    while(-not $sr.EndOfStream){
                        $before=[int64]$fs.Position
                        $line=$sr.ReadLine()
                        $after=[int64]$fs.Position
                        $lineBytes=[Math]::Max(1,$after-$before)
                        if([string]::IsNullOrWhiteSpace($line)){continue}
                        try{$evt=$line|ConvertFrom-Json;Apply-Event $index $evt $month $lineBytes;$dirty=$true}catch{}
                    }
                    $offset=[int64]$fs.Position
                }finally{$sr.Dispose()}
            }finally{$fs.Dispose()}
            $state.files|Add-Member -NotePropertyName $file.Name -NotePropertyValue $offset -Force
        }

        if($dirty -and ((Get-Date)-$lastWrite).TotalSeconds -ge 2){
            $index.updatedAt=(Get-Date).ToString("o")
            $state.updatedAt=$index.updatedAt
            Write-AtomicUtf8File $indexPath ($index|ConvertTo-Json -Depth 15)
            Save-State $state
            $dirty=$false
            $lastWrite=Get-Date
        }
        Start-Sleep -Milliseconds 250
    }
}finally{
    if($dirty){
        try{
            $index.updatedAt=(Get-Date).ToString("o")
            $state.updatedAt=$index.updatedAt
            Write-AtomicUtf8File $indexPath ($index|ConvertTo-Json -Depth 15)
            Save-State $state
        }catch{}
    }
    try{$mutex.ReleaseMutex()}catch{}
    try{$mutex.Dispose()}catch{}
}
