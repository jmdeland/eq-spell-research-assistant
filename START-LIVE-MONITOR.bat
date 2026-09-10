@echo off
setlocal
cd /d "%~dp0"
title EQ Spell Research Assistant - Live Monitor
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0live-monitor.ps1"
if errorlevel 1 (
  echo.
  echo The live monitor stopped with an error.
  pause
)
