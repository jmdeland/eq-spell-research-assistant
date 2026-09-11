@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0INSTALL-DESKTOP-SHORTCUT.ps1"
if errorlevel 1 pause
