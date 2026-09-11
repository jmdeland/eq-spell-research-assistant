Option Explicit
Dim shell, fso, root, ps, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
ps = fso.BuildPath(root, "research-tool-tray.ps1")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & ps & """ -Root """ & root & """"
shell.Run cmd, 0, False
