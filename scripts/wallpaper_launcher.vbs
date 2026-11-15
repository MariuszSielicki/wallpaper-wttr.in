' wallpaper_launcher.vbs
' Version: 1.0.0
' Launches wallpaper.ps1 with a fully hidden window (no console flash).
' Resolves its own folder dynamically, so it works regardless of install path.

Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -NoProfile -File """ & scriptDir & "\wallpaper.ps1""", 0, False
