Option Explicit
' Hidden launcher for the DSH frpc tunnel.
' Launches C:\frp\frpc.exe with window style 0 (no console window at all).
' Idempotent: does nothing if an frpc.exe process is already running.

Dim wmi, procs, shell
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
Set procs = wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name = 'frpc.exe'")
If procs.Count = 0 Then
    Set shell = CreateObject("WScript.Shell")
    shell.Run """C:\frp\frpc.exe"" -c ""C:\frp\frpc.toml""", 0, False
End If
