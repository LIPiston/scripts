# Win11 service tuning: gaming-first, keeps WSL2 working.
# ASCII only on purpose - PowerShell 5.1 decodes BOM-less .ps1 with the ANSI codepage
# (GBK here) and a mangled multibyte comment can swallow the following line.
[CmdletBinding()]
param(
    [switch]$WhatIf
)

$Disable = @(
    'DiagTrack','dmwappushservice','WSAIFabricSvc','InventorySvc','DusmSvc','MapsBroker',
    'WMPNetworkSvc','PhoneSvc','SEMgrSvc','SmsRouter','WalletService','workfolderssvc',
    'RetailDemo','smphost','TieringEngineService','ALG','AxInstSV',
    'DPS','WdiServiceHost','WdiSystemHost','lfsvc','TrkWks'
)
$Manual = @('BITS','WSearch')

# Must stay startable - WSL2, devices, security, remote access.
$Keep = @(
    'WSLService','WslInstaller','vmcompute','hns','HvHost',
    'bthserv','BTAGService','BthAvctpSvc','MTKBTSVC',
    'GameInputSvc','GameInputRedistService','XboxGipSvc','hidserv',
    'AMD External Events Utility','AmdPpkgSvc','amdpmfservice',
    'NVDisplay.ContainerLocalSystem','nvagent',
    'mpssvc','BFE','HipsDaemon','HRWSCCtrl',
    'sshd','ssh-agent','Tailscale','RustDesk',
    'WbioSrvc','NcdAutoSetup','SharedAccess','SSDPSRV','fdPHost','FDResPub','GameViewerService'
)

$ReportDir = Join-Path $PSScriptRoot 'out'
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir | Out-Null }
$report   = Join-Path $ReportDir 'report.txt'
$rollback = Join-Path $ReportDir 'rollback-generated.ps1'

# ---- self-elevate -------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Requesting administrator rights (UAC prompt)...'
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -PassThru
    Write-Host "Elevated run finished (exit code $($p.ExitCode)). See $report"
    return
}

function To-StartupType([string]$m) {
    switch ($m) { 'Auto' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { 'Manual' } }
}

# ---- apply --------------------------------------------------------------
$lines = @('# Win11 service tuning rollback - run as administrator')
$rows  = @('Service|Before|After|StateNow')

foreach ($n in ($Disable + $Manual)) {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
    if (-not $svc) { $rows += "$n|NOT_FOUND|-|-"; continue }
    $before = $svc.StartMode
    $want   = if ($Disable -contains $n) { 'Disabled' } else { 'Manual' }
    if ($WhatIf) { $rows += "$n|$before|(WhatIf) $want|-"; continue }
    try {
        if ($want -eq 'Disabled') {
            if ($svc.State -eq 'Running') { Stop-Service -Name $n -Force -ErrorAction Stop }
            Set-Service -Name $n -StartupType Disabled -ErrorAction Stop
        } else {
            Set-Service -Name $n -StartupType Manual -ErrorAction Stop
        }
    } catch {
        $rows += "$n|$before|ERROR: $($_.Exception.Message)|-"
        continue
    }
    $after = (Get-CimInstance Win32_Service -Filter "Name='$n'").StartMode
    $state = (Get-Service -Name $n -ErrorAction SilentlyContinue).Status
    $rows += "$n|$before|$after|$state"
    if ($before -ne $after) {
        $lines += "Set-Service -Name $n -StartupType $(To-StartupType $before)"
    }
}

# ---- verify the keep list ----------------------------------------------
$rows += ''
$rows += '=== KEEP LIST ==='
foreach ($n in $Keep) {
    $s = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
    if ($s) { $rows += ("{0,-32} {1,-9} {2}" -f $n, $s.StartMode, $s.State) }
    else    { $rows += "$n  MISSING" }
}

$lines | Set-Content -Path $rollback -Encoding ASCII
$rows  | Set-Content -Path $report   -Encoding UTF8
$rows | ForEach-Object { Write-Host $_ }
Write-Host "Rollback script: $rollback"
