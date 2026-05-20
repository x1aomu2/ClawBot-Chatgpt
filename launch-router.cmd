@ECHO off
SETLOCAL
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-router.ps1"
set "exitcode=%errorlevel%"
if not "%exitcode%"=="0" (
  echo.
  echo Launch failed with exit code %exitcode%.
  pause
)
exit /b %exitcode%
