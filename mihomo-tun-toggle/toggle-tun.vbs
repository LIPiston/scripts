Option Explicit

Const CONFIG_PATH = "C:\Users\LIPis\AppData\Roaming\mihomo-party\mihomo.yaml"
Const SHORTCUT_PATH = "C:\Users\LIPis\Desktop\tun.lnk"
Const PWSH_ICON = "C:\Users\LIPis\scoop\shims\pwsh.exe,0"
Const CMD_ICON = "C:\Windows\System32\cmd.exe,0"

Dim fso, shell, currentEnabled, expectedEnabled, args
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
Set args = WScript.Arguments

currentEnabled = ReadTunEnabled()
expectedEnabled = Not currentEnabled

If args.Count = 0 Or LCase(args(0)) <> "--dry-run" Then
    WScript.Sleep 150
    shell.SendKeys "^%."
    WScript.Sleep 2000
End If

Dim resultingEnabled
resultingEnabled = ReadTunEnabled()
If resultingEnabled = currentEnabled And expectedEnabled <> currentEnabled Then
    resultingEnabled = expectedEnabled
End If

UpdateShortcutIcon resultingEnabled

Function ReadTunEnabled()
    Dim file, line, trimmed, inTun
    ReadTunEnabled = False
    inTun = False
    If Not fso.FileExists(CONFIG_PATH) Then Exit Function
    Set file = fso.OpenTextFile(CONFIG_PATH, 1, False, -1)
    Do Until file.AtEndOfStream
        line = file.ReadLine
        trimmed = Trim(line)
        If trimmed = "tun:" Then
            inTun = True
        ElseIf inTun And Len(line) > 0 And Left(line, 1) <> " " And Left(line, 1) <> vbTab Then
            Exit Do
        ElseIf inTun And LCase(trimmed) = "enable: true" Then
            ReadTunEnabled = True
            Exit Do
        ElseIf inTun And LCase(trimmed) = "enable: false" Then
            ReadTunEnabled = False
            Exit Do
        End If
    Loop
    file.Close
End Function

Sub UpdateShortcutIcon(enabled)
    Dim shortcut
    Set shortcut = shell.CreateShortcut(SHORTCUT_PATH)
    If enabled Then
        shortcut.IconLocation = PWSH_ICON
    Else
        shortcut.IconLocation = CMD_ICON
    End If
    shortcut.Save
End Sub
