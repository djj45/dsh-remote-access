@echo off
rem Manual stop for the DSH frpc tunnel.
taskkill /IM frpc.exe /F
if errorlevel 1 echo frpc is not running.
