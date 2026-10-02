param([switch]$NoPause,[switch]$RefreshOnly)

$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms

$root=$PSScriptRoot
$desktop=[Environment]::GetFolderPath('Desktop')
$shortcutPath=Join-Path $desktop 'EverQuest Research & Loot Tool.lnk'
$vbs=Join-Path $root 'EverQuest Research & Loot Tool.vbs'
$icon=Join-Path $root 'EverQuestResearchLoot.ico'
$wscript=Join-Path $env:WINDIR 'System32\\wscript.exe'

$portableDataRoot=Join-Path $root 'portable-data'
$userDataRoot=Join-Path $env:LOCALAPPDATA 'EverQuest Research & Loot Tool'
$desktopHistoryRoot=Join-Path $userDataRoot 'history'
$portableHistoryRoot=Join-Path $portableDataRoot 'history'


function Install-PersistentDesktopLauncher {
    param([string]$ApplicationRoot)

    if(-not(Test-Path -LiteralPath $userDataRoot)){
        New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null
    }

    $version='current'
    try{
        $versionPath=Join-Path $ApplicationRoot 'app-version.json'
        if(Test-Path -LiteralPath $versionPath){
            $version=[string]((Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json).version)
        }
    }catch{}
    $safeVersion=($version -replace '[^0-9A-Za-z._-]','_')

    $installRootPath=Join-Path $userDataRoot 'install-root.txt'
    Set-Content -LiteralPath $installRootPath -Value $ApplicationRoot -Encoding Unicode

    $persistentLauncher=Join-Path $userDataRoot 'EverQuest Research & Loot Tool Launcher.vbs'
    $launcher=@'
Option Explicit
Dim shell, fso, dataRoot, rootFile, appRoot, trayScript, ts, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dataRoot = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\EverQuest Research & Loot Tool")
rootFile = fso.BuildPath(dataRoot, "install-root.txt")
If Not fso.FileExists(rootFile) Then
  shell.Popup "The desktop app location is not configured. Run START HERE.bat from the current EverQuest Research & Loot Tool folder and choose Desktop Mode.", 0, "EverQuest Research & Loot Tool", 48
  WScript.Quit 2
End If
Set ts = fso.OpenTextFile(rootFile, 1, False, -1)
appRoot = Trim(ts.ReadLine)
ts.Close
trayScript = fso.BuildPath(appRoot, "research-tool-tray.ps1")
If Not fso.FileExists(trayScript) Then
  shell.Popup "The saved application folder no longer exists or is incomplete:" & vbCrLf & appRoot & vbCrLf & vbCrLf & "Run START HERE.bat from the current folder and choose Desktop Mode to repair the shortcut.", 0, "EverQuest Research & Loot Tool", 48
  WScript.Quit 3
End If
shell.CurrentDirectory = shell.ExpandEnvironmentStrings("%TEMP%")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & trayScript & """ -Root """ & appRoot & """"
shell.Run cmd, 0, False
'@
    Set-Content -LiteralPath $persistentLauncher -Value $launcher -Encoding ASCII

    $sourceIcon=Join-Path $ApplicationRoot 'EverQuestResearchLoot.ico'
    $persistentIcon=Join-Path $userDataRoot ("EverQuestResearchLoot-"+$safeVersion+".ico")
    if(Test-Path -LiteralPath $sourceIcon){ Copy-Item -LiteralPath $sourceIcon -Destination $persistentIcon -Force }

    # A version-specific icon path avoids Windows continuing to display a cached icon from an older build.
    try{
        Get-ChildItem -LiteralPath $userDataRoot -Filter 'EverQuestResearchLoot-*.ico' -File -ErrorAction SilentlyContinue |
            Where-Object {$_.FullName -ne $persistentIcon} |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 2 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }catch{}

    $desktop=[Environment]::GetFolderPath('Desktop')
    $shortcutPath=Join-Path $desktop 'EverQuest Research & Loot Tool.lnk'
    $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
    if(Test-Path -LiteralPath $shortcutPath){ Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue }
    $ws=New-Object -ComObject WScript.Shell
    $sc=$ws.CreateShortcut($shortcutPath)
    $sc.TargetPath=$wscript
    $sc.Arguments='"'+$persistentLauncher+'"'
    $sc.WorkingDirectory=$env:TEMP
    if(Test-Path -LiteralPath $persistentIcon){$sc.IconLocation=$persistentIcon+',0'}
    $sc.Description='Launch EverQuest Research & Loot Tool'
    $sc.Save()

    return [pscustomobject]@{Shortcut=$shortcutPath;Launcher=$persistentLauncher;Icon=$persistentIcon;Version=$version}
}

function Get-PortableUserFiles {
    if(-not(Test-Path -LiteralPath $portableDataRoot)){ return @() }

    $skipNames=@(
        'tray.pid',
        'update-shutdown-request.json',
        'suppress-browser-once.flag',
        'loot-history-index.json',
        'history-index-worker-state.json'
    )

    return @(
        Get-ChildItem -LiteralPath $portableDataRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $skipNames -notcontains $_.Name -and
            $_.Name -notlike 'loot-history-????-??.jsonl'
        }
    )
}

function Backup-DesktopData {
    if(-not(Test-Path -LiteralPath $userDataRoot)){ return $null }
    $existing=@(Get-ChildItem -LiteralPath $userDataRoot -Force -ErrorAction SilentlyContinue)
    if($existing.Count -eq 0){ return $null }

    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot=Join-Path $env:LOCALAPPDATA ("EverQuest Research & Loot Tool_backup_"+$stamp)
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    foreach($item in $existing){
        Copy-Item -LiteralPath $item.FullName -Destination $backupRoot -Recurse -Force
    }

    return $backupRoot
}

function Get-HistoryKey {
    param([string]$Line)
    if([string]::IsNullOrWhiteSpace($Line)){ return $null }
    try{
        $evt=$Line | ConvertFrom-Json
        if($evt -and $evt.PSObject.Properties['historyId'] -and -not [string]::IsNullOrWhiteSpace([string]$evt.historyId)){
            return ('id:'+[string]$evt.historyId)
        }
    }catch{}
    return ('raw:'+$Line)
}

function Read-HistoryLines {
    param([string]$Path)
    if(-not(Test-Path -LiteralPath $Path)){ return @() }
    return @(Get-Content -LiteralPath $Path -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Write-Utf8NoBomLines {
    param([string]$Path,[string[]]$Lines)
    $parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $parent)){ New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $tmp=$Path+'.merge-'+[guid]::NewGuid().ToString('N')+'.tmp'
    $utf8=New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($tmp,$Lines,$utf8)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Merge-HistoryArchives {
    if(-not(Test-Path -LiteralPath $desktopHistoryRoot)){ New-Item -ItemType Directory -Path $desktopHistoryRoot -Force | Out-Null }

    $names=@()
    if(Test-Path -LiteralPath $desktopHistoryRoot){
        $names += @(Get-ChildItem -LiteralPath $desktopHistoryRoot -Filter 'loot-history-????-??.jsonl' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    }
    if(Test-Path -LiteralPath $portableHistoryRoot){
        $names += @(Get-ChildItem -LiteralPath $portableHistoryRoot -Filter 'loot-history-????-??.jsonl' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    }
    $names=@($names | Sort-Object -Unique)

    $desktopCount=0
    $portableCount=0
    $duplicateCount=0
    $mergedCount=0

    foreach($name in $names){
        $desktopPath=Join-Path $desktopHistoryRoot $name
        $portablePath=Join-Path $portableHistoryRoot $name
        $desktopLines=Read-HistoryLines $desktopPath
        $portableLines=Read-HistoryLines $portablePath

        $desktopCount += $desktopLines.Count
        $portableCount += $portableLines.Count

        $seen=New-Object 'System.Collections.Generic.HashSet[string]'
        $merged=New-Object 'System.Collections.Generic.List[string]'

        foreach($line in @($desktopLines)+@($portableLines)){
            $key=Get-HistoryKey $line
            if($null -eq $key){ continue }
            if($seen.Add($key)){
                [void]$merged.Add($line)
            } else {
                $duplicateCount++
            }
        }

        Write-Utf8NoBomLines -Path $desktopPath -Lines @($merged)
        $mergedCount += $merged.Count
    }

    # Raw monthly archives are authoritative. Force the history worker to rebuild its index.
    Remove-Item -LiteralPath (Join-Path $desktopHistoryRoot 'loot-history-index.json') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $desktopHistoryRoot 'history-index-worker-state.json') -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        DesktopRecords=$desktopCount
        PortableRecords=$portableCount
        DuplicatesSkipped=$duplicateCount
        MergedRecords=$mergedCount
        ArchiveCount=$names.Count
    }
}

function Copy-PortableNonHistoryData {
    param([System.IO.FileInfo[]]$SourceFiles)

    if(-not(Test-Path -LiteralPath $userDataRoot)){
        New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null
    }

    $copied=0
    foreach($file in $SourceFiles){
        $relative=$file.FullName.Substring($portableDataRoot.Length).TrimStart('\\')
        $destination=Join-Path $userDataRoot $relative
        $destinationDir=Split-Path -Parent $destination

        if(-not(Test-Path -LiteralPath $destinationDir)){
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force

        if(-not(Test-Path -LiteralPath $destination)){
            throw "Portable-data migration verification failed. Missing destination: $destination"
        }
        if((Get-Item -LiteralPath $destination).Length -ne $file.Length){
            throw "Portable-data migration verification failed. Size mismatch: $destination"
        }
        $copied++
    }
    return $copied
}

if(-not $RefreshOnly){
Clear-Host
Write-Host ''
Write-Host 'EverQuest Research & Loot Tool - Desktop Setup' -ForegroundColor Cyan
Write-Host ('Application folder: ' + $root)
Write-Host ''

$portableFiles=Get-PortableUserFiles
$portableHistoryFiles=@()
if(Test-Path -LiteralPath $portableHistoryRoot){
    $portableHistoryFiles=@(Get-ChildItem -LiteralPath $portableHistoryRoot -Filter 'loot-history-????-??.jsonl' -File -ErrorAction SilentlyContinue)
}
$portableDataDetected=($portableFiles.Count -gt 0 -or $portableHistoryFiles.Count -gt 0)

if($portableDataDetected){
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host 'PORTABLE DATA DETECTED' -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host ('Portable data folder: ' + $portableDataRoot)
    Write-Host ('Portable non-history files found: ' + $portableFiles.Count)
    Write-Host ('Portable history archives found: ' + $portableHistoryFiles.Count)
    Write-Host ''
    Write-Host 'Migration will BACK UP existing Desktop data first.' -ForegroundColor Green
    Write-Host 'Observed Loot History will be MERGED, never overwritten.' -ForegroundColor Green
    Write-Host 'The portable copy will NOT be deleted or moved.' -ForegroundColor Green
    Write-Host ''

    do {
        $answer=(Read-Host 'Import your existing portable data into Desktop mode? [Y/N]').Trim().ToUpperInvariant()
    } while($answer -ne 'Y' -and $answer -ne 'N')

    if($answer -eq 'Y'){
        Write-Host ''
        Write-Host 'Creating Desktop data backup...' -ForegroundColor Cyan
        $backupRoot=Backup-DesktopData
        if($backupRoot){
            Write-Host ('Backup created: ' + $backupRoot) -ForegroundColor Green
        } else {
            Write-Host 'No existing Desktop data required backup.' -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host 'Merging Observed Loot History...' -ForegroundColor Cyan
        $historyResult=Merge-HistoryArchives
        Write-Host ('Desktop history records found:  ' + $historyResult.DesktopRecords)
        Write-Host ('Portable history records found: ' + $historyResult.PortableRecords)
        Write-Host ('Duplicate records skipped:      ' + $historyResult.DuplicatesSkipped)
        Write-Host ('Merged history records:         ' + $historyResult.MergedRecords) -ForegroundColor Green
        Write-Host ('Monthly archives processed:     ' + $historyResult.ArchiveCount)

        Write-Host ''
        Write-Host 'Copying remaining portable data...' -ForegroundColor Cyan
        $copied=Copy-PortableNonHistoryData -SourceFiles $portableFiles
        Write-Host ("Portable-data migration verified: {0} non-history file(s) copied." -f $copied) -ForegroundColor Green
        Write-Host ('Desktop data folder: ' + $userDataRoot)
        Write-Host 'Portable data remains unchanged as a backup.' -ForegroundColor Green
        if($backupRoot){ Write-Host ('Pre-migration Desktop backup: ' + $backupRoot) -ForegroundColor Green }
    } else {
        Write-Host ''
        Write-Host 'Portable data was NOT imported.' -ForegroundColor Yellow
        Write-Host 'Your portable data remains unchanged.'
    }
} else {
    Write-Host 'No portable user data was detected. Desktop setup will continue.' -ForegroundColor DarkGray
}

}

Write-Host ''
if(-not(Test-Path -LiteralPath $vbs)){throw "Launcher not found: $vbs"}
$desktopInstall=Install-PersistentDesktopLauncher -ApplicationRoot $root
Write-Host 'Desktop launcher refreshed successfully.' -ForegroundColor Green
Write-Host ('Shortcut: ' + $desktopInstall.Shortcut)
Write-Host ('Current app: ' + $root)
Write-Host ('Launcher: ' + $desktopInstall.Launcher)
Write-Host ('Icon: ' + $desktopInstall.Icon)
Write-Host ''
if(-not $NoPause){Read-Host 'Press Enter to close Desktop Setup'}
