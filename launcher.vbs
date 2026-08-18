' Launcher: run PowerShell script with hidden window (no black console)
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & baseDir & "\daily-ai-recommend.ps1""", 0, False
