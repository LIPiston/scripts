# 作者 LIPiston
# 作用 Steam 账号切换器，用于快速在多个 Steam 账号间切换
# 支持平台 Windows
# 需要和 SteamSwitcher.bat 放在同一目录下运行
# 运行bat即可，运行bat即可，运行bat即可 
#
# --- 功能说明 ---
# 1. 读取 Steam 登录用户列表
# 2. 交互式选择要切换的账号
# 3. 修改登录配置并启动 Steam

$ErrorActionPreference = 'Stop'

# 设置 Windows 控制台和 PowerShell 管道为 UTF-8
chcp 65001 > $null
$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$steamPath = $null
$regPaths = @(
    'HKCU:\Software\Valve\Steam',
    'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
    'HKLM:\SOFTWARE\Valve\Steam'
)

foreach ($p in $regPaths) {
    try {
        $v = Get-ItemProperty -Path $p -ErrorAction Stop
        if ($v.SteamPath) {
            $steamPath = $v.SteamPath
            break
        }
        if ($v.InstallPath) {
            $steamPath = $v.InstallPath
            break
        }
    } catch {}
}

if (-not $steamPath -or -not (Test-Path -LiteralPath $steamPath)) {
    Write-Host '未找到 Steam 安装目录。'
    Read-Host '按回车退出'
    exit 1
}

$loginFile = Join-Path $steamPath 'config\loginusers.vdf'
if (-not (Test-Path -LiteralPath $loginFile)) {
    Write-Host ('未找到账号文件: ' + $loginFile)
    Write-Host '请先至少登录过一次 Steam。'
    Read-Host '按回车退出'
    exit 1
}

$text = Get-Content -LiteralPath $loginFile -Raw -Encoding UTF8
$matches = [regex]::Matches($text, '(?s)"(?<sid>\d{17})"\s*\{(?<body>.*?)\n\s*\}')
$users = @()

foreach ($m in $matches) {
    $body = $m.Groups['body'].Value
    $account = ([regex]::Match($body, '"AccountName"\s+"(?<v>[^"]*)"')).Groups['v'].Value

    if ([string]::IsNullOrWhiteSpace($account)) {
        continue
    }

    $persona = ([regex]::Match($body, '"PersonaName"\s+"(?<v>[^"]*)"')).Groups['v'].Value
    $mostRecent = ([regex]::Match($body, '"MostRecent"\s+"(?<v>[^"]*)"')).Groups['v'].Value
    $fields = [ordered]@{}

    foreach ($field in [regex]::Matches($body, '"(?<k>[^"]+)"\s+"(?<v>[^"]*)"')) {
        $fields[$field.Groups['k'].Value] = $field.Groups['v'].Value
    }

    $users += [pscustomobject]@{
        SteamID = $m.Groups['sid'].Value
        AccountName = $account
        PersonaName = $persona
        MostRecent = $mostRecent
        Fields = $fields
    }
}

if ($users.Count -eq 0) {
    Write-Host '没有读取到已保存的 Steam 账号。'
    Write-Host '请确认 Steam 已勾选“记住我”并登录过账号。'
    Read-Host '按回车退出'
    exit 1
}

Write-Host ''
Write-Host '已读取到以下 Steam 账号:'
Write-Host ''

for ($i = 0; $i -lt $users.Count; $i++) {
    $u = $users[$i]
    $recent = if ($u.MostRecent -eq '1') { ' *当前/最近' } else { '' }
    $name = if ($u.PersonaName) { $u.PersonaName } else { '无昵称' }
    Write-Host ('[{0}] {1} ({2}){3}' -f ($i + 1), $u.AccountName, $name, $recent)
}

Write-Host ''
$choice = Read-Host '请输入要切换的序号'
$n = 0

if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $users.Count) {
    Write-Host '输入无效。'
    Read-Host '按回车退出'
    exit 1
}

$selected = $users[$n - 1]
$running = Get-Process steam -ErrorAction SilentlyContinue

if ($running) {
    Write-Host '正在关闭 Steam...'
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
}

$loginKey = 'HKCU:\Software\Valve\Steam'
if (-not (Test-Path -LiteralPath $loginKey)) {
    New-Item -Path $loginKey -Force | Out-Null
}

Set-ItemProperty -Path $loginKey -Name AutoLoginUser -Value $selected.AccountName -Type String
Set-ItemProperty -Path $loginKey -Name RememberPassword -Value 1 -Type DWord

$backupFile = $loginFile + '.bak.' + (Get-Date -Format 'yyyyMMddHHmmss')
Copy-Item -LiteralPath $loginFile -Destination $backupFile -Force

# SteamTools only changes the selected user to MostRecent and keeps passwords remembered.
# Rewrite the VDF from parsed fields so the brace structure cannot be corrupted.
foreach ($u in $users) {
    $u.Fields['MostRecent'] = if ($u.SteamID -eq $selected.SteamID) { '1' } else { '0' }

    if ($u.SteamID -eq $selected.SteamID) {
        $u.Fields['RememberPassword'] = '1'
        $u.Fields['AllowAutoLogin'] = '1'
    }
}

$builder = [System.Text.StringBuilder]::new()
[void]$builder.AppendLine('"users"')
[void]$builder.AppendLine('{')

foreach ($u in $users) {
    [void]$builder.AppendLine("`t`"$($u.SteamID)`"")
    [void]$builder.AppendLine("`t{")

    foreach ($key in $u.Fields.Keys) {
        $value = $u.Fields[$key]
        [void]$builder.AppendLine("`t`t`"$key`"`t`t`"$value`"")
    }

    [void]$builder.AppendLine("`t}")
}

[void]$builder.AppendLine('}')
[System.IO.File]::WriteAllText($loginFile, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))

$steamExe = Join-Path $steamPath 'steam.exe'
if (-not (Test-Path -LiteralPath $steamExe)) {
    Write-Host ('未找到 steam.exe: ' + $steamExe)
    Read-Host '按回车退出'
    exit 1
}

Write-Host ('正在启动 Steam，并切换到账号: ' + $selected.AccountName)
Start-Process -FilePath $steamExe
Write-Host ''
Write-Host '完成。如果 Steam 仍要求密码，说明该账号本机未保存有效登录凭据，需要手动登录一次并勾选记住我。'
Start-Sleep -Seconds 3
