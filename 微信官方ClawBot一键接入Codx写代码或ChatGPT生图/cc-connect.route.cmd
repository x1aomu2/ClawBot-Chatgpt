@ECHO off
SETLOCAL
if exist "%~dp0router.env.cmd" call "%~dp0router.env.cmd"
cc-connect.cmd --config "%~dp0config.route.toml" --force
