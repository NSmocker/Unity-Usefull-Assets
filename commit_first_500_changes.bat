@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
echo Running PowerShell batch helper...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0commit_first_500_changes.ps1"
set "EXITCODE=%ERRORLEVEL%"
echo.
echo PowerShell finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
