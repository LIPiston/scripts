# Rollback for the service changes applied on 2026-09-28.
# Run as administrator. Only startup types are restored - nothing was deleted.
Set-Service -Name DiagTrack -StartupType Automatic
Set-Service -Name dmwappushservice -StartupType Manual
Set-Service -Name WSAIFabricSvc -StartupType Automatic
Set-Service -Name InventorySvc -StartupType Automatic
Set-Service -Name DusmSvc -StartupType Automatic
Set-Service -Name MapsBroker -StartupType Automatic
Set-Service -Name WMPNetworkSvc -StartupType Manual
Set-Service -Name PhoneSvc -StartupType Manual
Set-Service -Name SEMgrSvc -StartupType Manual
Set-Service -Name SmsRouter -StartupType Manual
Set-Service -Name WalletService -StartupType Manual
Set-Service -Name workfolderssvc -StartupType Manual
Set-Service -Name RetailDemo -StartupType Manual
Set-Service -Name smphost -StartupType Manual
Set-Service -Name TieringEngineService -StartupType Manual
Set-Service -Name ALG -StartupType Manual
Set-Service -Name AxInstSV -StartupType Manual
Set-Service -Name DPS -StartupType Automatic
Set-Service -Name WdiServiceHost -StartupType Manual
Set-Service -Name WdiSystemHost -StartupType Manual
Set-Service -Name lfsvc -StartupType Manual
Set-Service -Name TrkWks -StartupType Automatic
Set-Service -Name BITS -StartupType Automatic
Set-Service -Name WSearch -StartupType Automatic
Write-Host 'Rollback done.'
