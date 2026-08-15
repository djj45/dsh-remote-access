@echo off
rem Starts frpc minimized unless an instance is already running.
rem Installed to the current user's Startup folder by install-frpc.ps1.
tasklist /FI "IMAGENAME eq frpc.exe" 2>NUL | find /I "frpc.exe" >NUL
if %ERRORLEVEL%==0 exit /b
start "DSH-Tunnel" /min C:\frp\frpc.exe -c C:\frp\frpc.toml
