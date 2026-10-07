# Restore the services Phone Link (Windows 11 "Phone Service") needs.
# ASCII only on purpose - PowerShell 5.1 decodes BOM-less .ps1 with the ANSI codepage.
[CmdletBinding()]
param(
    [switch]$WhatIf
)

# Inbox defaults: all three are Trigger-Started / Manual, so they still do not
# start at boot - they only come up when Phone Link / SMS actually asks for them.
$Restore = @(
    @{ Name = 'PhoneSvc';  Type = 'Manual'; Start = $true  },
    @{ Name = 'SmsRouter'; Type = 'Manual'; Start = $false }
)

$Report = Join-Path $env:LOCALAPPDATA 'Temp\phone_link_restore.txt'
$lines  = @()

# ---- self-elevate -------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Requesting administrator rights (UAC prompt)...'
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -PassThru
    Write-Host "Elevated run finished (exit code $($p.ExitCode)). Report: $Report"
    return
}

$lines += "=== Phone Link restore  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
$lines += 'Service|Before|After|StateNow'

foreach ($item in $Restore) {
    $n = $item.Name
    $svc = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
    if (-not $svc) { $lines += "$n|NOT_FOUND|-|-"; continue }
    $before = $svc.StartMode
    if ($WhatIf) { $lines += "$n|$before|(WhatIf) $($item.Type)|$($svc.State)"; continue }
    try {
        Set-Service -Name $n -StartupType $item.Type -ErrorAction Stop
        if ($item.Start) {
            Start-Service -Name $n -ErrorAction Stop
        }
    } catch {
        $lines += "$n|$before|ERROR: $($_.Exception.Message)|-"
        continue
    }
    $after = (Get-CimInstance Win32_Service -Filter "Name='$n'").StartMode
    $state = (Get-Service -Name $n -ErrorAction SilentlyContinue).Status
    $lines += "$n|$before|$after|$state"
}

$lines += ''
$lines += '=== TriggerInfo keys (should be intact) ==='
foreach ($n in @('PhoneSvc','SmsRouter')) {
    $t = @(Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\$n\TriggerInfo" -ErrorAction SilentlyContinue)
    $lines += "$n  triggers=$($t.Count)"
}

$lines += ''
$lines += '=== Phone Link / cross-device packages ==='
Get-AppxPackage | Where-Object { $_.Name -match 'CrossDevice|YourPhone' } |
    Select-Object Name, Version, Status |
    ForEach-Object { $lines += ("{0}  {1}  {2}" -f $_.Name, $_.Version, $_.Status) }

$lines += ''
$lines += '=== Supporting stack (must stay Running) ==='
foreach ($n in @('CDPSvc','DevicesFlowUserSvc','BluetoothUserService','bthserv','WpnService')) {
    $s = Get-CimInstance Win32_Service -Filter "Name LIKE '$n%'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($s) { $lines += ("{0,-24} {1,-9} {2}" -f $s.Name, $s.StartMode, $s.State) }
}

$lines | Set-Content -Path $Report -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
