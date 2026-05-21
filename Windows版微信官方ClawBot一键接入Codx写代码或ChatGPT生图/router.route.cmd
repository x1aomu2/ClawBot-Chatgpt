@ECHO off
SETLOCAL
if exist "%~dp0router.env.cmd" call "%~dp0router.env.cmd"
set "ROUTER_CONFIG_FILE=%~dp0config.route.toml"
node "%~dp0router.mjs" agent %*
