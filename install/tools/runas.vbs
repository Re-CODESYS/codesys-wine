' Run a program elevated ("runas") under WINE, e.g. APInstaller.CLI.exe add-on installs:
'   wine wscript C:\path\runas.vbs "C:\Program Files (x86)\CODESYS\APInstaller\APInstaller.CLI.exe" --getInstallations
' The elevated program runs detached; redirect its output from a .cmd wrapper if needed.
Set a = WScript.Arguments
args = ""
For i = 1 To a.Count - 1
  args = args & " """ & a(i) & """"
Next
CreateObject("Shell.Application").ShellExecute a(0), args, "", "runas", 0
