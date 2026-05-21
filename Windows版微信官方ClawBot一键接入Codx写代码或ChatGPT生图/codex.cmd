@ECHO off
SETLOCAL
if /I "%~1"=="--version" (
  echo codex-cli 0.0.0-router
  exit /b 0
)
if /I "%~1"=="-V" (
  echo codex-cli 0.0.0-router
  exit /b 0
)
if /I "%~1"=="version" (
  echo codex-cli 0.0.0-router
  exit /b 0
)
if /I "%~1"=="--help" (
  echo Codex-compatible router shim
  exit /b 0
)
if /I "%~1"=="-h" (
  echo Codex-compatible router shim
  exit /b 0
)
call "%~dp0router.route.cmd" %*
