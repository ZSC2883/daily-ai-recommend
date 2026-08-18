' Launcher: run server.js with hidden window (no black console)
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run "node """ & baseDir & "\server.js""", 0, False
