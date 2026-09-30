$ErrorActionPreference = 'Stop'

$wshell = New-Object -ComObject WScript.Shell

# Send Mihomo Party's TUN toggle shortcut.
Start-Sleep -Milliseconds 150
$wshell.SendKeys('^%.')

Write-Host 'TUN 切换指令已发送。'
