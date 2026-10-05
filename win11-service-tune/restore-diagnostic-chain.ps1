# Restore the Windows diagnostic chain to its inbox default start type (Manual).
# Fixes the empty "battery usage" graph in Settings > Power & battery, which is
# fed by E3 / SRUM energy attribution that DPS and the WDI hosts provide.
# Run as administrator. Nothing is deleted - only the Start type changes.
# ASCII only on purpose (PowerShell 5.1 + ANSI codepage).
[CmdletBinding()]
param()

$Targets = @(
    'DPS',            # Diagnostic Policy Service
    'WdiServiceHost', # Diagnostic Service Host
    'WdiSystemHost'   # Diagnostic System Host
)

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Requesting administrator rights (UAC prompt)...'
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") `
        -Verb RunAs -Wait
    return
}

foreach ($n in $Targets) {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Host "$n NOT FOUND"; continue }
    $before = $svc.StartMode
    try { Set-Service -Name $n -StartupType Manual -ErrorAction Stop }
    catch { Write-Host "$n ERROR: $($_.Exception.Message)"; continue }
    $after = (Get-CimInstance Win32_Service -Filter "Name='$n'").StartMode
    Write-Host ("{0,-18} {1} -> {2}" -f $n, $before, $after)
}
Write-Host 'Done. Reboot, then leave the laptop on battery for a while and reopen Settings > Power & battery.'
