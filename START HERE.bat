@echo off
title EverQuest Research & Loot Tool - Easy Start
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0START-HERE.ps1"
if errorlevel 1 (
  echo.
  echo Easy Start encountered a problem.
  pause
)
