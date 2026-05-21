@ECHO off
SETLOCAL
chcp 65001 >nul
cd /d "%~dp0"
if not defined LAUNCH_ROUTER_USE_SAVED set "LAUNCH_ROUTER_USE_SAVED=1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-router.ps1"
set "exitcode=%errorlevel%"
if not "%exitcode%"=="0" (
  echo.
  echo Launch failed with exit code %exitcode%.
)
echo.
echo launch-router.cmd finished with exit code %exitcode%.
echo The service keeps running in the background if exit code is 0.
pause
exit /b %exitcode%
