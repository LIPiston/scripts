# Microsoft Edit 快速编辑器安装脚本
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipConfig
)

$ErrorActionPreference = 'Stop'
$editExe = Join-Path $env:WINDIR 'System32\edit.exe'
$configDir = Join-Path $env:APPDATA 'Microsoft\Edit'
$configPath = Join-Path $configDir 'settings.json'

if (-not (Test-Path -LiteralPath $editExe)) {
    throw "找不到 Microsoft Edit：$editExe"
}

$version = (& $editExe --version 2>&1 | Out-String).Trim()
Write-Host "检测到：$version"

if (-not $SkipConfig) {
    $config = @'
{
  "files.associations": {
    "*.env": "shell",
    "*.conf": "ini",
    "*.service": "ini",
    "*.jsonc": "json"
  }
}
'@
    if (-not (Test-Path -LiteralPath $configDir)) {
        if ($PSCmdlet.ShouldProcess($configDir, '创建 Microsoft Edit 用户配置目录')) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
    }
    if (-not (Test-Path -LiteralPath $configPath)) {
        if ($PSCmdlet.ShouldProcess($configPath, '创建 Microsoft Edit 用户配置')) {
            [System.IO.File]::WriteAllText($configPath, $config, [System.Text.UTF8Encoding]::new($false))
        }
    } else {
        Write-Host "保留已有配置，不覆盖：$configPath" -ForegroundColor Yellow
    }
}

Write-Host "Microsoft Edit 安装检查完成。"
Write-Host "下一步运行：.\register-edit-context-menu.ps1"
