:: 作者: LIPiston
:: 与 wifi.ps1 一起使用

chcp 65001 >nul

powershell.exe -command ^ "& {Unblock-File .\wifi.ps1}"
powershell.exe -command ^ "& {set-executionpolicy Unrestricted -Scope Process; .'.\wifi.ps1' }"