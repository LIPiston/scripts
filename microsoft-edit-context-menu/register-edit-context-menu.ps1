# Microsoft Edit 右键菜单注册脚本
[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$menuName = 'Use Edit'
$menuKey = 'MicrosoftEdit'
$command = 'wt.exe -w 0 new-tab --title "Use Edit" edit "%1"'
$icon = Join-Path $env:WINDIR 'System32\edit.exe'
$extensions = @(
    '.txt','.json','.jsonc','.yaml','.yml','.md','.markdown','.toml','.ini','.conf','.env',
    '.xml','.csv','.tsv','.log','.config','.properties','.sh','.bash','.zsh','.bat','.cmd','.ps1',
    '.py','.js','.jsx','.ts','.tsx','.html','.htm','.css','.scss','.less','.sql','.graphql','.gql',
    '.vue','.svelte','.rs','.go','.java','.c','.h','.cpp','.hpp','.cs','.swift','.kt','.kts',
    '.lua','.rb','.php','.tex','.gitignore','.gitattributes','.dockerfile'
)

foreach ($extension in $extensions) {
    $path = "Software\Classes\SystemFileAssociations\$extension\shell\$menuKey"
    if ($PSCmdlet.ShouldProcess("HKCU\$path", "注册 $menuName")) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
        try {
            $key.SetValue('', $menuName, [Microsoft.Win32.RegistryValueKind]::String)
            $key.SetValue('Icon', $icon, [Microsoft.Win32.RegistryValueKind]::String)
            $commandKey = $key.CreateSubKey('command')
            try { $commandKey.SetValue('', $command, [Microsoft.Win32.RegistryValueKind]::String) }
            finally { $commandKey.Close() }
        } finally { $key.Close() }
    }
}

Start-Process -FilePath (Join-Path $env:WINDIR 'System32\ie4uinit.exe') -ArgumentList '-show' -Wait -WindowStyle Hidden
Write-Host "已为 $($extensions.Count) 个扩展名注册右键菜单：$menuName"
Write-Host '仅写入当前用户 HKCU，不改变默认打开方式。'
