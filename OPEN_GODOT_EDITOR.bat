@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PLAY_STAR_WARFARE.ps1" -Editor
if errorlevel 1 pause
