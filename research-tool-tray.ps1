param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = [IO.Path]::GetFullPath($Root)
$monitorScript = Join-Path $root 'live-monitor.ps1'
$iconPath = Join-Path $root 'EverQuestResearchLoot.ico'
$toolUrl = 'http://127.0.0.1:8765/index.html'
$userDataRoot = Join-Path $env:LOCALAPPDATA 'EverQuest Research & Loot Tool'
if(-not (Test-Path -LiteralPath $userDataRoot)){New-Item -ItemType Directory -Path $userDataRoot -Force | Out-Null}
$trayPidPath = Join-Path $userDataRoot 'tray.pid'
$shutdownRequestPath = Join-Path $userDataRoot 'shutdown-for-update.request'
$appVersionPath = Join-Path $root 'app-version.json'
$expectedVersion = ''
try {
    if(Test-Path -LiteralPath $appVersionPath){$expectedVersion=[string]((Get-Content -LiteralPath $appVersionPath -Raw | ConvertFrom-Json).version)}
} catch {}
Remove-Item -LiteralPath $shutdownRequestPath -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $trayPidPath -Value ([string]$PID) -Encoding ASCII

if(-not (Test-Path -LiteralPath $monitorScript)){[Windows.Forms.MessageBox]::Show('live-monitor.ps1 was not found. Re-extract the application package.','EverQuest Research & Loot Tool',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null; exit 1}

# Reuse the local companion only when it is the same build. If a stale build owns
# the dedicated port, ask its tray to exit and stop the stale listener before starting.
$alreadyRunning = $false
$staleCompanion = $false
try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8765/api/status' -TimeoutSec 1
    if($r.StatusCode -eq 200){
        $status=$null
        try{$status=$r.Content | ConvertFrom-Json}catch{}
        $runningVersion=$(if($status -and $status.version){[string]$status.version}else{''})
        $looksLikeOurApp=$status -and (($status.app -eq 'EverQuest Research & Loot Tool') -or $status.PSObject.Properties.Name -contains 'logFile')
        if($looksLikeOurApp -and $expectedVersion -and $runningVersion -eq $expectedVersion){
            $alreadyRunning=$true
        } elseif($looksLikeOurApp){
            $staleCompanion=$true
        }
    }
} catch {}

if($staleCompanion){
    # Newer trays observe this request file. This also safely no-ops for older trays.
    try{Set-Content -LiteralPath $shutdownRequestPath -Value 'launcher-version-mismatch' -Encoding ASCII}catch{}
    $deadline=(Get-Date).AddSeconds(5)
    while((Get-Date) -lt $deadline){
        Start-Sleep -Milliseconds 250
        try {
            $probe=Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8765/api/status' -TimeoutSec 1
            if($probe.StatusCode -ne 200){break}
        } catch {break}
    }
    # If the stale monitor survived, stop only the process that owns our dedicated port.
    try {
        $conn=Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if($conn -and $conn.OwningProcess){Stop-Process -Id ([int]$conn.OwningProcess) -Force -ErrorAction SilentlyContinue}
    } catch {}
    Start-Sleep -Milliseconds 400
}

$monitor = $null
if(-not $alreadyRunning){
    $monitor = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$monitorScript) -WorkingDirectory $root -WindowStyle Hidden -PassThru
}

$notify = New-Object Windows.Forms.NotifyIcon
if(Test-Path -LiteralPath $iconPath){
    $iconStream=$null;$sourceIcon=$null
    try{
        $iconStream=[IO.File]::Open($iconPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $sourceIcon=New-Object Drawing.Icon($iconStream)
        $notify.Icon=$sourceIcon.Clone()
    } finally {
        if($sourceIcon){$sourceIcon.Dispose()}
        if($iconStream){$iconStream.Dispose()}
    }
}else{$notify.Icon=[Drawing.SystemIcons]::Application}
$notify.Text = 'EverQuest Research & Loot Tool'
$notify.Visible = $true

$menu = New-Object Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('Open Research Tool')
$statusItem = $menu.Items.Add('Monitor Status: Starting...')
$statusItem.Enabled = $false
$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator)) | Out-Null
$restartItem = $menu.Items.Add('Restart Monitor')
$exitItem = $menu.Items.Add('Exit')
$notify.ContextMenuStrip = $menu

function Test-Companion {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8765/api/status' -TimeoutSec 1
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}
function Open-Tool { Start-Process $toolUrl }
function Start-Monitor {
    if(Test-Companion){ return }
    $script:monitor = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$monitorScript) -WorkingDirectory $root -WindowStyle Hidden -PassThru
}
function Stop-Monitor {
    if($script:monitor -and -not $script:monitor.HasExited){
        try { Stop-Process -Id $script:monitor.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
}

$openItem.add_Click({Open-Tool})
$notify.add_DoubleClick({Open-Tool})
$restartItem.add_Click({
    Stop-Monitor
    Start-Sleep -Milliseconds 400
    Start-Monitor
    Start-Sleep -Milliseconds 700
    Open-Tool
})
$exitItem.add_Click({
    $answer=[Windows.Forms.MessageBox]::Show("Exit EverQuest Research & Loot Tool?`r`n`r`nLive loot monitoring will stop until the application is started again.",'Exit Research & Loot Tool',[Windows.Forms.MessageBoxButtons]::OKCancel,[Windows.Forms.MessageBoxIcon]::Warning)
    if($answer -eq [Windows.Forms.DialogResult]::OK){
        Stop-Monitor
        $notify.Visible=$false
        [Windows.Forms.Application]::Exit()
    }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 1500
$timer.add_Tick({
    if(Test-Path -LiteralPath $shutdownRequestPath){
        Stop-Monitor
        Remove-Item -LiteralPath $shutdownRequestPath -Force -ErrorAction SilentlyContinue
        $notify.Visible=$false
        [Windows.Forms.Application]::Exit()
        return
    }
    if(Test-Companion){
        $statusItem.Text='Monitor Status: Online'
        $notify.Text='EverQuest Research & Loot Tool - Online'
    } else {
        $statusItem.Text='Monitor Status: Offline'
        $notify.Text='EverQuest Research & Loot Tool - Offline'
    }
})
$timer.Start()

# The live monitor normally opens the browser itself. If reusing an existing companion, open it here.
if($alreadyRunning){Open-Tool}

try {[Windows.Forms.Application]::Run()} finally {
    $timer.Stop();$timer.Dispose();$notify.Visible=$false;$notify.Dispose()
    Remove-Item -LiteralPath $trayPidPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $shutdownRequestPath -Force -ErrorAction SilentlyContinue
}

