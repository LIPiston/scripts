# Win11 service tuning: gaming-first, keeps WSL2 working.
# ASCII only on purpose - PowerShell 5.1 decodes BOM-less .ps1 with the ANSI codepage
# (GBK here) and a mangled multibyte comment can swallow the following line.
#
# REVISED 2026-10-07 (FINAL): PhoneSvc / SmsRouter are BACK on the disable list, because
# the Phone Link app itself was removed. The two changes must go together - see
# references/phone-link-repair.md:
#   * Phone Link installed  -> PhoneSvc/SmsRouter MUST be Manual, or the app reports
#     "service is turned off" and looks broken.
#   * Phone Link removed    -> disable both (they are Manual + trigger-started, so the
#     only thing keeping them off is this setting) AND uninstall the packages:
#       Get-AppxPackage -AllUsers -Name Microsoft.YourPhone | Remove-AppxPackage -AllUsers
#       Get-AppxPackage -AllUsers -Name MicrosoftWindows.CrossDevice | Remove-AppxPackage -AllUsers
#     Disabling the services alone leaves ~479 MB of inert Appx on disk.
# An earlier revision of this file removed both from the list while the app was still
# installed; that was reverted by the same day's final decision.
# REVISED 2026-10-05 (1): DPS / WdiServiceHost / WdiSystemHost were REMOVED from the
# disable list. Disabling the diagnostic chain silently kills the "battery usage"
# graph in Settings > Power & battery (plus powercfg /energy, sleepstudy and WDI ETL
# tracing). See README "Breakage found on 2026-10-05". Run
# restore-diagnostic-chain.ps1 to put them back on a machine already trimmed.
# REVISED 2026-10-05 (2): most entries are Windows inbox defaults that never start
# anyway (Start=4 + State=1223 since first boot). Disabling them frees nothing, so
# they are SKIPPED and reported instead of counted as a win. Pass
# -IncludeInboxDefaults to force the old behaviour.
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$IncludeInboxDefaults
)

$Disable = @(
    'DiagTrack','dmwappushservice','WSAIFabricSvc','InventorySvc','DusmSvc','MapsBroker',
    'WMPNetworkSvc','PhoneSvc','SEMgrSvc','SmsRouter','WalletService','workfolderssvc',
    'RetailDemo','smphost','TieringEngineService','ALG','AxInstSV',
    'lfsvc','TrkWks'
)
$Manual = @('BITS','WSearch')

# Never disable: this chain is the service context for SRUM / Energy Estimation
# attribution, WDI energy tracing and powercfg /energy. Disabling it empties the
# battery-usage graph. All three are Manual (on demand) on a clean install.
$NeverDisable = @('DPS','WdiServiceHost','WdiSystemHost')

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
# NOTE: PhoneSvc / SmsRouter are deliberately NOT in $Keep. They are in $Disable because
# the Phone Link app was uninstalled on 2026-10-07. If you reinstall Phone Link
# (winget install --id 9NMPJ99VJBWV --source msstore), move them to $Keep or Microsoft.YourPhone
# will report "service is turned off". See the header and references/phone-link-repair.md.

$ReportDir = Join-Path $PSScriptRoot 'out'
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir | Out-Null }
$report   = Join-Path $ReportDir 'report.txt'
$rollback = Join-Path $ReportDir 'rollback-generated.ps1'

# ---- self-elevate -------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $WhatIf) {
    Write-Host 'Requesting administrator rights (UAC prompt)...'
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -PassThru
    Write-Host "Elevated run finished (exit code $($p.ExitCode)). See $report"
    return
}

function To-StartupType([string]$m) {
    switch ($m) { 'Auto' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { 'Manual' } }
}

# ---- guard: the lists must not contradict each other --------------------
$clash = $Disable | Where-Object { $NeverDisable -contains $_ }
if ($clash) { throw "Refusing to run: $($clash -join ', ') is on the never-disable list." }

# ---- apply --------------------------------------------------------------
$lines = @('# Win11 service tuning rollback - run as administrator')
$rows  = @('Service|Before|After|StateNow|Note')

foreach ($n in ($Disable + $Manual)) {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
    if (-not $svc) { $rows += "$n|NOT_FOUND|-|-|"; continue }
    $before = $svc.StartMode
    $want   = if ($Disable -contains $n) { 'Disabled' } else { 'Manual' }

    # Already Disabled and Stopped = inbox default that never ran. Not a saving.
    if (-not $IncludeInboxDefaults -and $before -eq 'Disabled' -and $svc.State -eq 'Stopped') {
        $rows += "$n|$before|(skipped)|$($svc.State)|already disabled - no saving"
        continue
    }
    if ($WhatIf) { $rows += "$n|$before|(WhatIf) $want|-|"; continue }

    try {
        if ($want -eq 'Disabled') {
            if ($svc.State -eq 'Running') { Stop-Service -Name $n -Force -ErrorAction Stop }
            Set-Service -Name $n -StartupType Disabled -ErrorAction Stop
        } else {
            Set-Service -Name $n -StartupType Manual -ErrorAction Stop
        }
    } catch {
        $rows += "$n|$before|ERROR: $($_.Exception.Message)|-|"
        continue
    }
    $after = (Get-CimInstance Win32_Service -Filter "Name='$n'").StartMode
    $state = (Get-Service -Name $n -ErrorAction SilentlyContinue).Status
    $rows += "$n|$before|$after|$state|"
    if ($before -ne $after) {
        $lines += "Set-Service -Name '$n' -StartupType $(To-StartupType $before)"
    }
}

# ---- verify the never-disable + keep lists ------------------------------
$rows += ''
$rows += '=== NEVER DISABLE (must stay Manual or Automatic) ==='
foreach ($n in $NeverDisable) {
    $s = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
    if ($s) { $rows += ("{0,-32} {1,-9} {2}" -f $n, $s.StartMode, $s.State) } else { $rows += "$n  MISSING" }
}
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
