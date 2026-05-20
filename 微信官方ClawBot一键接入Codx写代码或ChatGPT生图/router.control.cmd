@ECHO off
SETLOCAL
if exist "%~dp0router.env.local.cmd" call "%~dp0router.env.local.cmd" >nul
node "%~dp0router.mjs" control %*
