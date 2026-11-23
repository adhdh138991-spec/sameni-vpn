@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP_AND_BUILD.ps1"
echo.
echo (log saved in setup_log.txt)
pause
