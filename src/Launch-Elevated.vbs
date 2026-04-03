Dim sh, fso, scriptDir, launcher, args
Set sh  = CreateObject("Shell.Application")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
launcher  = scriptDir & "\Launch-LabTools.ps1"
args      = "-NoLogo -ExecutionPolicy Bypass -File """ & launcher & """"
sh.ShellExecute "pwsh.exe", args, scriptDir, "runas", 1
