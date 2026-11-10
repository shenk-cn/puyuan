@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0puyuan.ps1" %*
exit /b %errorlevel%
