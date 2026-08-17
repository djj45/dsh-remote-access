# Windows one-shot installer for the DSH frpc tunnel.
#
# Usage (PowerShell, run on the Windows machine that hosts DSH):
#   .\install-frpc.ps1 -ServerAddr 111.230.57.237 -Token "FRP_TOKEN"
#
# Optional parameters:
#   -ServerPort 7000   -LocalPort 3080   -RemotePort 18080
#   -ProxyName dsh-win -InstallDir C:\frp
#   -FrpVersion 0.71.0 -DownloadBase https://gh.djj45.com
#   -StartNow          start frpc immediately (default when not already running)
param(
    [Parameter(Mandatory = $true)][string]$ServerAddr,
    [Parameter(Mandatory = $true)][string]$Token,
    [int]$ServerPort = 7000,
    [int]$LocalPort = 3080,
    [int]$RemotePort = 18080,
    [string]$ProxyName = 'dsh-win',
    [string]$InstallDir = 'C:\frp',
    [string]$FrpVersion = '0.71.0',
    [string]$DownloadBase = 'https://gh.djj45.com',
    [switch]$StartNow
)

$ErrorActionPreference = 'Stop'

Write-Host "==> Preparing $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$zip = Join-Path $InstallDir "frp_${FrpVersion}_windows_amd64.zip"
$url = "${DownloadBase}/https://github.com/fatedier/frp/releases/download/v${FrpVersion}/frp_${FrpVersion}_windows_amd64.zip"
if (-not (Test-Path -LiteralPath $zip)) {
    Write-Host "==> Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip
}

Write-Host "==> Extracting frp v$FrpVersion"
Expand-Archive -LiteralPath $zip -DestinationPath $InstallDir -Force
$frpcSrc = Join-Path $InstallDir "frp_${FrpVersion}_windows_amd64\frpc.exe"
$frpcExe = Join-Path $InstallDir 'frpc.exe'
Copy-Item -LiteralPath $frpcSrc -Destination $frpcExe -Force
Unblock-File -LiteralPath $frpcExe -ErrorAction SilentlyContinue

Write-Host "==> Writing frpc.toml"
$config = @"
serverAddr = "$ServerAddr"
serverPort = $ServerPort
auth.method = "token"
auth.token = "$Token"
transport.tls.enable = true
log.to = "C:/frp/frpc.log"
log.level = "info"
log.maxDays = 7

[[proxies]]
name = "$ProxyName"
type = "tcp"
localIP = "127.0.0.1"
localPort = $LocalPort
remotePort = $RemotePort
"@
$config = $config -replace "`r", ''
Set-Content -LiteralPath (Join-Path $InstallDir 'frpc.toml') -Value $config -Encoding ascii -NoNewline

Write-Host "==> Installing hidden logon startup script"
$cmdTemplate = @'
@echo off
rem Manual start for the DSH frpc tunnel. No console window is shown.
wscript.exe "__INSTALL_DIR__\DSH-Tunnel-Win.vbs"
'@
$cmd = $cmdTemplate.Replace('__INSTALL_DIR__', $InstallDir)
$cmdPath = Join-Path $InstallDir 'DSH-Tunnel-Win.cmd'
Set-Content -LiteralPath $cmdPath -Value $cmd -Encoding ascii -NoNewline

$vbsTemplate = @'
Option Explicit
' Hidden launcher for the DSH frpc tunnel.
' Launches frpc with window style 0 (no console window at all).
' Idempotent: does nothing if an frpc.exe process is already running.

Dim wmi, procs, shell
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
Set procs = wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name = 'frpc.exe'")
If procs.Count = 0 Then
    Set shell = CreateObject("WScript.Shell")
    shell.Run """__INSTALL_DIR__\frpc.exe"" -c ""__INSTALL_DIR__\frpc.toml""", 0, False
End If
'@
$vbs = $vbsTemplate.Replace('__INSTALL_DIR__', $InstallDir)
$vbsPath = Join-Path $InstallDir 'DSH-Tunnel-Win.vbs'
Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ascii -NoNewline

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
Copy-Item -LiteralPath $vbsPath -Destination $startupDir -Force
Remove-Item -LiteralPath (Join-Path $startupDir 'DSH-Tunnel-Win.cmd') -Force -ErrorAction SilentlyContinue

Write-Host "==> Trying elevated SYSTEM auto-start task (optional)"
try {
    schtasks /Create /TN 'DSH-Tunnel-Win' /TR "`"$frpcExe`" -c `"$(Join-Path $InstallDir 'frpc.toml')`"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F | Out-Host
    Write-Host "    SYSTEM task registered."
} catch {
    Write-Host "    No admin rights; logon-startup script will be used instead."
}

$running = Get-Process frpc -ErrorAction SilentlyContinue
if ($StartNow -or -not $running) {
    Write-Host "==> Starting frpc now (hidden)"
    try {
        wscript.exe $vbsPath
    } catch {
        Write-Host "    Could not start frpc from this shell: $($_.Exception.Message)"
        Write-Host "    Double-click $vbsPath or log off/on to start it."
    }
}

Write-Host ""
Write-Host "==> Done."
Write-Host "    config : $(Join-Path $InstallDir 'frpc.toml')"
Write-Host "    log    : C:\frp\frpc.log"
Write-Host "    manual start: $vbsPath"
Write-Host "    Check log for 'login to server success' and 'start proxy success'."
