param()
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$portableData=Join-Path $root 'portable-data'
$desktopData=Join-Path $env:LOCALAPPDATA 'EverQuest Research & Loot Tool'
$portableLauncher=Join-Path $root 'EverQuest Research & Loot Tool Portable.vbs'
$desktopLauncher=Join-Path $root 'EverQuest Research & Loot Tool.vbs'
$desktopInstaller=Join-Path $root 'INSTALL-DESKTOP-SHORTCUT.ps1'
$testSetup=Join-Path $root 'TEST-SETUP.ps1'
function Header {
 Clear-Host
 Write-Host ''
 Write-Host '============================================================' -ForegroundColor Cyan
 Write-Host ' EverQuest Research & Loot Tool by Bromm' -ForegroundColor Cyan
 Write-Host ' Easy Start' -ForegroundColor Cyan
 Write-Host '============================================================' -ForegroundColor Cyan
 Write-Host ''
}
function Has-PortableData {
 if(-not(Test-Path -LiteralPath $portableData)){ return $false }
 return (@(Get-ChildItem -LiteralPath $portableData -Recurse -File -Force -ErrorAction SilentlyContinue).Count -gt 0)
}
function Has-DesktopData {
 if(-not(Test-Path -LiteralPath $desktopData)){ return $false }
 return (@(Get-ChildItem -LiteralPath $desktopData -Recurse -File -Force -ErrorAction SilentlyContinue).Count -gt 0)
}
function Start-Vbs([string]$Path) {
 if(-not(Test-Path -LiteralPath $Path)){ throw "Launcher not found: $Path" }
 Start-Process -FilePath (Join-Path $env:WINDIR 'System32\\wscript.exe') -ArgumentList @("""$Path""")
}
while($true){
 Header
 $portableExists=Has-PortableData
 $desktopExists=Has-DesktopData
 if($portableExists){ Write-Host 'Portable data detected in this folder.' -ForegroundColor Green }
 if($desktopExists){ Write-Host 'Desktop-mode data detected on this PC.' -ForegroundColor Green }
 if($portableExists -or $desktopExists){ Write-Host '' }
 Write-Host 'Choose how you want to run the tool:'
 Write-Host ''
 Write-Host '  1  Try / Continue Portable Mode' -ForegroundColor Yellow
 Write-Host '     Runs from this folder. No installation required.'
 Write-Host ''
 Write-Host '  2  Desktop Mode' -ForegroundColor Yellow
 Write-Host '     Creates a desktop shortcut and keeps data in Windows AppData.'
 if($portableExists){ Write-Host '     Your portable data can be copied safely into Desktop Mode.' -ForegroundColor Green }
 Write-Host ''
 Write-Host '  3  Check / Repair Setup' -ForegroundColor Yellow
 Write-Host '     Checks the EverQuest log and local app components.'
 Write-Host ''
 Write-Host '  4  Exit'
 Write-Host ''
 $choice=(Read-Host 'Enter 1, 2, 3, or 4').Trim()
 switch($choice){
  '1' {
   Write-Host ''
   $marker=Join-Path $portableData 'desktop-import-complete.json'
   if($desktopExists -and -not(Test-Path -LiteralPath $marker)){
    Write-Host 'Existing Desktop data was found on this PC.' -ForegroundColor Green
    Write-Host 'You can copy your settings and safely MERGE your Observed Loot History into Portable Mode.'
    Write-Host 'Your Desktop data will remain unchanged.'
    Write-Host ''
    do{$a=(Read-Host 'Use your existing Desktop data in Portable Mode? [Y/N]').Trim().ToUpperInvariant()}while($a -ne 'Y' -and $a -ne 'N')
    if($a -eq 'Y'){
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'IMPORT-DESKTOP-TO-PORTABLE.ps1')
      if($LASTEXITCODE -ne 0){Write-Host 'Data import did not complete. Portable Mode was not started.' -ForegroundColor Red;Read-Host 'Press Enter';continue}
    }
   }
   Write-Host ''; Write-Host 'Starting Portable Mode...' -ForegroundColor Cyan; Start-Vbs $portableLauncher; Write-Host 'The tool is starting in your web browser.' -ForegroundColor Green; Start-Sleep -Seconds 2; exit 0
  }
  '2' { Write-Host ''; Write-Host 'Preparing Desktop Mode...' -ForegroundColor Cyan; & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $desktopInstaller -NoPause; if($LASTEXITCODE -ne 0){Write-Host '';Write-Host 'Desktop setup did not complete successfully.' -ForegroundColor Red;Read-Host 'Press Enter to return to Easy Start';continue}; Write-Host '';Write-Host 'Starting Desktop Mode...' -ForegroundColor Cyan;Start-Vbs $desktopLauncher;Write-Host 'The tool is starting in your web browser.' -ForegroundColor Green;Start-Sleep -Seconds 2;exit 0 }
  '3' { & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $testSetup }
  '4' { exit 0 }
  default { Write-Host '';Write-Host 'Please enter 1, 2, 3, or 4.' -ForegroundColor Yellow;Start-Sleep -Seconds 1 }
 }
}
