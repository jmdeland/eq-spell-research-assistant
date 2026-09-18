$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms

$root=$PSScriptRoot
$desktop=[Environment]::GetFolderPath('Desktop')
$shortcutPath=Join-Path $desktop 'EverQuest Research & Loot Tool.lnk'
$vbs=Join-Path $root 'EverQuest Research & Loot Tool.vbs'
$icon=Join-Path $root 'EverQuestResearchLoot.ico'
$wscript=Join-Path $env:WINDIR 'System32\wscript.exe'

if(-not(Test-Path -LiteralPath $vbs)){throw "Launcher not found: $vbs"}

# Replace any existing shortcut with the same product name so an older
# extracted copy cannot remain pinned behind the normal desktop icon.
if(Test-Path -LiteralPath $shortcutPath){
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
}

$ws=New-Object -ComObject WScript.Shell
$sc=$ws.CreateShortcut($shortcutPath)
$sc.TargetPath=$wscript
$sc.Arguments='"'+$vbs+'"'
$sc.WorkingDirectory=$env:TEMP
$sc.IconLocation=$icon+',0'
$sc.Description='Launch EverQuest Research & Loot Tool'
$sc.Save()

# Remember the canonical active application root for diagnostics/self-repair.
$userDataRoot=Join-Path $env:LOCALAPPDATA 'EverQuest Research & Loot Tool'
if(-not(Test-Path -LiteralPath $userDataRoot)){New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null}
Set-Content -LiteralPath (Join-Path $userDataRoot 'install-root.txt') -Value $root -Encoding UTF8

[Windows.Forms.MessageBox]::Show(
    "Desktop shortcut refreshed successfully.`r`n`r`nCurrent app:`r`n$root",
    'EverQuest Research & Loot Tool'
) | Out-Null
