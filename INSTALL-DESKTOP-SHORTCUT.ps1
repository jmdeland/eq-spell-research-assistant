$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$root=$PSScriptRoot
$desktop=[Environment]::GetFolderPath('Desktop')
$shortcutPath=Join-Path $desktop 'EverQuest Research & Loot Tool.lnk'
$vbs=Join-Path $root 'EverQuest Research & Loot Tool.vbs'
$icon=Join-Path $root 'EverQuestResearchLoot.ico'
$wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
$ws=New-Object -ComObject WScript.Shell
$sc=$ws.CreateShortcut($shortcutPath)
$sc.TargetPath=$wscript
$sc.Arguments='"'+$vbs+'"'
$sc.WorkingDirectory=$root
$sc.IconLocation=$icon+',0'
$sc.Description='Launch EverQuest Research & Loot Tool'
$sc.Save()
[Windows.Forms.MessageBox]::Show('Desktop shortcut created successfully.','EverQuest Research & Loot Tool') | Out-Null
