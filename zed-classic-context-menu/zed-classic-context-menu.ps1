[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$ListOnly,
    [switch]$InstallZed,
    [switch]$RemoveZed,
    [switch]$NonInteractive,
    [string]$ZedExe = ""
)

$ErrorActionPreference = 'Stop'
$Script:ToolName = 'ZedClassicContextMenu'
$Script:CreatedMarker = 'CreatedByZedClassicContextMenu'

function Write-Title {
    param([string]$Text)
    Write-Host ""
    Write-Host "==== $Text ====" -ForegroundColor Cyan
}

function Get-RegistryValue {
    param([Microsoft.Win32.RegistryKey]$Key, [string]$Name)
    try { return $Key.GetValue($Name, $null) } catch { return $null }
}

function Open-ClassesRoot {
    param([string]$Path)
    $base = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes', $false)
    if (-not $base) { return $null }
    return $base.OpenSubKey($Path, $false)
}

function Resolve-ZedExe {
    param([string]$ExplicitPath)
    if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Zed i18n\Zed.exe",
        "$env:LOCALAPPDATA\Programs\Zed\Zed.exe",
        "$env:LOCALAPPDATA\Programs\Zed\zed.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\zed.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $cmd = Get-Command zed.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function New-MenuCandidate {
    param(
        [string]$Id,
        [string]$Source,
        [string]$Name,
        [string]$Title,
        [string]$Icon,
        [string]$Command,
        [string]$ExplorerCommandHandler,
        [string]$AppliesTo,
        [string]$Kind
    )
    [pscustomobject]@{
        Id = $Id
        Source = $Source
        Name = $Name
        Title = $Title
        Icon = $Icon
        Command = $Command
        ExplorerCommandHandler = $ExplorerCommandHandler
        AppliesTo = $AppliesTo
        Kind = $Kind
    }
}

function Get-ShellCandidatesFromHive {
    param([string]$HiveLabel, [Microsoft.Win32.RegistryKey]$ClassesRoot)

    $scopes = @(
        @{ Scope='Files'; Path='*\shell'; Target='*' },
        @{ Scope='Folders'; Path='Directory\shell'; Target='Directory' },
        @{ Scope='FolderBackground'; Path='Directory\Background\shell'; Target='Directory\Background' },
        @{ Scope='Drives'; Path='Drive\shell'; Target='Drive' },
        @{ Scope='AllFilesystemObjects'; Path='AllFilesystemObjects\shell'; Target='AllFilesystemObjects' }
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($scope in $scopes) {
        $shell = $ClassesRoot.OpenSubKey($scope.Path, $false)
        if (-not $shell) { continue }
        foreach ($name in $shell.GetSubKeyNames()) {
            $key = $shell.OpenSubKey($name, $false)
            if (-not $key) { continue }
            $commandKey = $key.OpenSubKey('command', $false)
            $defaultTitle = Get-RegistryValue $key ''
            $title = @(Get-RegistryValue $key 'MUIVerb', Get-RegistryValue $key 'VerbName', $defaultTitle, $name) | Where-Object { $_ } | Select-Object -First 1
            $icon = Get-RegistryValue $key 'Icon'
            $handler = Get-RegistryValue $key 'ExplorerCommandHandler'
            $appliesTo = Get-RegistryValue $key 'AppliesTo'
            $command = if ($commandKey) { Get-RegistryValue $commandKey '' } else { $null }
            $items.Add((New-MenuCandidate -Id '' -Source "$HiveLabel\$($scope.Path)\$name" -Name $name -Title "$title" -Icon "$icon" -Command "$command" -ExplorerCommandHandler "$handler" -AppliesTo "$appliesTo" -Kind $scope.Scope)) | Out-Null
        }
    }
    return $items
}

function Get-ModernPackageCandidates {
    $items = New-Object System.Collections.Generic.List[object]
    $roots = @(
        @{ Label='HKCU'; Path='Software\Classes\PackagedCom\Package' },
        @{ Label='HKLM'; Path='Software\Classes\PackagedCom\Package' }
    )
    foreach ($rootSpec in $roots) {
        $hive = if ($rootSpec.Label -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
        $root = $hive.OpenSubKey($rootSpec.Path, $false)
        if (-not $root) { continue }
        foreach ($packageName in $root.GetSubKeyNames()) {
            if ($packageName -notmatch 'Zed|zed') { continue }
            $package = $root.OpenSubKey($packageName, $false)
            if (-not $package) { continue }
            $serverRoot = $package.OpenSubKey('Server', $false)
            if (-not $serverRoot) { continue }
            foreach ($serverName in $serverRoot.GetSubKeyNames()) {
                $server = $serverRoot.OpenSubKey($serverName, $false)
                if (-not $server) { continue }
                foreach ($classId in $server.GetSubKeyNames()) {
                    $classKey = $server.OpenSubKey($classId, $false)
                    if (-not $classKey) { continue }
                    $displayName = Get-RegistryValue $classKey 'DisplayName'
                    $appId = Get-RegistryValue $classKey 'AppId'
                    $identity = "$packageName $serverName $classId $displayName $appId"
                    if ($identity -match 'Zed|zed|Open') {
                        $items.Add((New-MenuCandidate -Id '' -Source "$($rootSpec.Label)\$($rootSpec.Path)\$packageName\Server\$serverName\$classId" -Name $serverName -Title "$displayName" -Icon '' -Command '' -ExplorerCommandHandler "$classId" -AppliesTo '' -Kind 'ModernPackage')) | Out-Null
                    }
                }
            }
        }
    }
    return $items
}

function Get-ContextMenuCandidates {
    $items = New-Object System.Collections.Generic.List[object]
    $hkcuClasses = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes', $false)
    if ($hkcuClasses) {
        (Get-ShellCandidatesFromHive -HiveLabel 'HKCU\Software\Classes' -ClassesRoot $hkcuClasses) | ForEach-Object { $items.Add($_) | Out-Null }
    }
    $hkcrClasses = [Microsoft.Win32.Registry]::ClassesRoot
    (Get-ShellCandidatesFromHive -HiveLabel 'HKCR' -ClassesRoot $hkcrClasses) | ForEach-Object { $items.Add($_) | Out-Null }
    (Get-ModernPackageCandidates) | ForEach-Object { $items.Add($_) | Out-Null }

    $seen = @{}
    $deduped = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        $key = "$($item.Source)|$($item.Title)|$($item.Command)|$($item.ExplorerCommandHandler)"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $item.Id = [string]($deduped.Count + 1)
            $deduped.Add($item) | Out-Null
        }
    }
    return $deduped
}

function Show-Candidates {
    param([object[]]$Candidates)
    if (-not $Candidates -or $Candidates.Count -eq 0) {
        Write-Host '没有读到可用的右键菜单候选项。' -ForegroundColor Yellow
        return
    }
    foreach ($item in $Candidates) {
        $title = if ($item.Title) { $item.Title } else { $item.Name }
        $commandHint = if ($item.Command) { $item.Command } elseif ($item.ExplorerCommandHandler) { "ExplorerCommandHandler=$($item.ExplorerCommandHandler)" } else { '(no command)' }
        Write-Host ("[{0}] {1}  ({2})" -f $item.Id, $title, $item.Kind) -ForegroundColor Green
        Write-Host "    Source : $($item.Source)"
        Write-Host "    Command: $commandHint"
        if ($item.Icon) { Write-Host "    Icon   : $($item.Icon)" }
    }
}

function Write-ClassicCommand {
    param(
        [string]$ClassesPath,
        [string]$KeyName,
        [string]$Title,
        [string]$Icon,
        [string]$Command
    )
    $keyPath = "HKCU:\Software\Classes\$ClassesPath\shell\$KeyName"
    $cmdPath = Join-Path $keyPath 'command'
    if ($PSCmdlet.ShouldProcess($keyPath, "write classic context menu command")) {
        New-Item -Path $cmdPath -Force | Out-Null
        Set-Item -Path $keyPath -Value $Title
        New-ItemProperty -Path $keyPath -Name 'MUIVerb' -Value $Title -PropertyType String -Force | Out-Null
        if ($Icon) { New-ItemProperty -Path $keyPath -Name 'Icon' -Value $Icon -PropertyType String -Force | Out-Null }
        New-ItemProperty -Path $keyPath -Name $Script:CreatedMarker -Value 1 -PropertyType DWord -Force | Out-Null
        Set-Item -Path $cmdPath -Value $Command
    }
}

function Install-ZedClassicMenu {
    param([string]$Exe)
    if (-not $Exe) { throw '找不到 Zed.exe。请用 -ZedExe "完整路径" 指定。' }
    $icon = "$Exe,0"
    Write-ClassicCommand -ClassesPath '*' -KeyName 'ZedClassicOpenFile' -Title '用 Zed 打开' -Icon $icon -Command "`"$Exe`" `"%1`""
    Write-ClassicCommand -ClassesPath 'Directory' -KeyName 'ZedClassicOpenFolder' -Title '用 Zed 打开文件夹' -Icon $icon -Command "`"$Exe`" `"%1`""
    Write-ClassicCommand -ClassesPath 'Directory\Background' -KeyName 'ZedClassicOpenHere' -Title '在 Zed 中打开此处' -Icon $icon -Command "`"$Exe`" `"%V`""
    Write-Host "Zed 经典右键菜单写入流程已完成。" -ForegroundColor Green
}

function Remove-ZedClassicMenu {
    $paths = @(
        'HKCU:\Software\Classes\*\shell\ZedClassicOpenFile',
        'HKCU:\Software\Classes\Directory\shell\ZedClassicOpenFolder',
        'HKCU:\Software\Classes\Directory\Background\shell\ZedClassicOpenHere'
    )
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            if ($PSCmdlet.ShouldProcess($path, 'remove classic context menu command')) {
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
    }
    Write-Host 'Zed 经典右键菜单删除流程已完成。' -ForegroundColor Green
}

function Copy-CandidateToClassicMenu {
    param([object]$Candidate)
    if (-not $Candidate.Command) {
        Write-Host '这个候选项只有 ExplorerCommandHandler，没有普通 command；经典二级菜单不能直接复用它。' -ForegroundColor Yellow
        Write-Host '如果这是 Zed，请选择内置的 Zed 修复项，它会用 Zed.exe 自动补一个普通 command。' -ForegroundColor Yellow
        return
    }
    $title = if ($Candidate.Title) { $Candidate.Title } else { $Candidate.Name }
    $safeName = ($Candidate.Name -replace '[^A-Za-z0-9_-]', '')
    if (-not $safeName) { $safeName = "Migrated$($Candidate.Id)" }
    $keyName = "MigratedBy$Script:ToolName$safeName"

    $targets = switch ($Candidate.Kind) {
        'Files' { @('*') }
        'Folders' { @('Directory') }
        'FolderBackground' { @('Directory\Background') }
        'Drives' { @('Drive') }
        'AllFilesystemObjects' { @('AllFilesystemObjects') }
        default { @('*', 'Directory') }
    }
    foreach ($target in $targets) {
        Write-ClassicCommand -ClassesPath $target -KeyName $keyName -Title $title -Icon $Candidate.Icon -Command $Candidate.Command
    }
    Write-Host "已复制：$title" -ForegroundColor Green
}

function Invoke-ShellAssociationRefresh {
    $source = @"
using System;
using System.Runtime.InteropServices;
public static class ShellRefresh {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@
    Add-Type -TypeDefinition $source -ErrorAction SilentlyContinue
    [ShellRefresh]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Invoke-Interactive {
    $zed = Resolve-ZedExe $ZedExe
    Write-Title 'Zed / Windows 11 经典右键菜单修复工具'
    Write-Host '用途：读取当前用户/系统注册表里的右键菜单候选项，选择要写到 Win10 风格「显示更多选项」菜单里的项目。'
    Write-Host '常用修复：关闭 Win11 初级菜单后，「用 Zed 打开」丢失 -> 选择 A 自动写入 Zed 经典菜单。'
    if ($zed) { Write-Host "检测到 Zed: $zed" -ForegroundColor Green } else { Write-Host '未自动检测到 Zed.exe。可退出后用 -ZedExe 指定。' -ForegroundColor Yellow }

    while ($true) {
        Write-Title '主菜单'
        Write-Host '[A] 自动把 Zed 放进经典二级菜单（推荐）'
        Write-Host '[L] 读取并列出当前右键菜单候选项'
        Write-Host '[C] 从候选项中选择一个有 command 的项目复制到经典菜单'
        Write-Host '[R] 删除本工具创建的 Zed 经典菜单'
        Write-Host '[Q] 退出'
        $choice = Read-Host '请选择'
        switch -Regex ($choice) {
            '^[Aa]$' {
                Install-ZedClassicMenu -Exe $zed
                Invoke-ShellAssociationRefresh
                pause
            }
            '^[Ll]$' {
                $c = Get-ContextMenuCandidates
                Show-Candidates $c
                pause
            }
            '^[Cc]$' {
                $c = Get-ContextMenuCandidates
                Show-Candidates $c
                $id = Read-Host '输入要复制的编号'
                $item = $c | Where-Object { $_.Id -eq $id } | Select-Object -First 1
                if ($item) {
                    Copy-CandidateToClassicMenu -Candidate $item
                    Invoke-ShellAssociationRefresh
                } else {
                    Write-Host '编号不存在。' -ForegroundColor Yellow
                }
                pause
            }
            '^[Rr]$' {
                Remove-ZedClassicMenu
                Invoke-ShellAssociationRefresh
                pause
            }
            '^[Qq]$' { return }
            default { Write-Host '无效选择。' -ForegroundColor Yellow }
        }
    }
}

if ($RemoveZed) {
    Remove-ZedClassicMenu
    Invoke-ShellAssociationRefresh
    return
}

if ($InstallZed) {
    Install-ZedClassicMenu -Exe (Resolve-ZedExe $ZedExe)
    Invoke-ShellAssociationRefresh
    return
}

if ($ListOnly) {
    Show-Candidates (Get-ContextMenuCandidates)
    return
}

if ($NonInteractive) {
    throw 'NonInteractive 需要同时指定 -InstallZed、-RemoveZed 或 -ListOnly。'
}

Invoke-Interactive
