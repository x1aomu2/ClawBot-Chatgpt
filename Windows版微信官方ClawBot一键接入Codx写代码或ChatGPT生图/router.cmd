@ECHO off
SETLOCAL
if exist "%~dp0router.env.cmd" call "%~dp0router.env.cmd"
node "%~dp0router.mjs" agent %*
