Set fs = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
base = fs.GetParentFolderName(WScript.ScriptFullName)
host = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
entry = fs.BuildPath(base, "Bootstrap.ps1")
If Not fs.FileExists(entry) Then
  MsgBox "ACE LowGear startup files are missing. Extract the complete source package.", 48, "ACE LowGear"
  WScript.Quit 1
End If
result = sh.Run(Chr(34) & host & Chr(34) & " -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & entry & Chr(34), 0, True)
If result <> 0 Then MsgBox "ACE LowGear could not start. Please use Start.cmd to view the startup message.", 48, "ACE LowGear"
WScript.Quit result
