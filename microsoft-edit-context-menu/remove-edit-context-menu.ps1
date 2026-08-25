# Microsoft Edit 右键菜单删除脚本
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
$menuKey = 'MicrosoftEdit'
$extensions = @(
    '.txt','.json','.jsonc','.yaml','.yml','.md','.markdown','.toml','.ini','.conf','.env',
    '.xml','.csv','.tsv','.log','.config','.properties','.sh','.bash','.zsh','.bat','.cmd','.ps1',
    '.py','.js','.jsx','.ts','.tsx','.html','.htm','.css','.scss','.less','.sql','.graphql','.gql',
    '.vue','.svelte','.rs','.go','.java','.c','.h','.cpp','.hpp','.cs','.swift','.kt','.kts',
    '.lua','.rb','.php','.tex','.gitignore','.gitattributes','.dockerfile'
)

$found = foreach ($extension in $extensions) {
    $path = "Software\Classes\SystemFileAssociations\$extension\shell\$menuKey"
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path, $false)
    if ($key) { $key.Close(); [pscustomobject]@{ Extension = $extension; Path = "HKCU\$path" } }
}

if (-not $found) {
    Write-Host '没有发现本工具注册的 Edit 右键菜单。'
    exit 0
}

Write-Host "发现 $($found.Count) 个待删除注册表键：" -ForegroundColor Yellow
$found | ForEach-Object { Write-Host "- $($_.Path)" }

if ($ListOnly) { exit 0 }

if (-not $PSCmdlet.ShouldProcess("$($found.Count) 个 HKCU 注册表键", '删除 Microsoft Edit 右键菜单')) {
    exit 0
}

foreach ($item in $found) {
    $path = "Software\Classes\SystemFileAssociations\$($item.Extension)\shell\$menuKey"
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($path, $false)
}

Start-Process -FilePath (Join-Path $env:WINDIR 'System32\ie4uinit.exe') -ArgumentList '-show' -Wait -WindowStyle Hidden
Write-Host "已删除 $($found.Count) 个 Edit 右键菜单注册表键。"
