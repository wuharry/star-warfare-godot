@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UPGRADE_TO_GODOT_4_7.ps1"
if errorlevel 1 pause
