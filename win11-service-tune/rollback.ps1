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

# --- batch B (2026-09-28) ---
Set-Service -Name Spooler -StartupType Automatic
Set-Service -Name StiSvc -StartupType Automatic
Set-Service -Name MRAfterSaleService -StartupType Automatic
Set-Service -Name NahimicService -StartupType Automatic
Set-Service -Name 'AMD Crash Defender Service' -StartupType Automatic
Set-Service -Name webthreatdefsvc -StartupType Manual
Set-Service -Name whesvc -StartupType Automatic
Set-Service -Name seclogon -StartupType Manual
sc.exe config webthreatdefusersvc start= auto
# sc.exe config webthreatdefusersvc_<luid> start= auto   # optional: instance, SCM usually refuses (87)
Write-Host 'Rollback done.'
