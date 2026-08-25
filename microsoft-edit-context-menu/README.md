# Microsoft Edit 右键菜单脚本

用于安装 Microsoft Edit 用户配置，以及为常用文本/配置文件注册或删除资源管理器右键菜单。

## 文件

- `install-edit.ps1`：检查 `C:\Windows\System32\edit.exe`，创建用户级 `settings.json`。已有配置不会覆盖。
- `register-edit-context-menu.ps1`：在当前用户 `HKCU\Software\Classes\SystemFileAssociations\<扩展名>` 下新增 `Use Edit`。
- `remove-edit-context-menu.ps1`：先列出待删除键，再删除本工具注册的菜单；不会修改默认文件关联。

## 安装

在 PowerShell 中运行：

```powershell
cd D:\LIPis\Documents\code\scripts\microsoft-edit-context-menu
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install-edit.ps1
.\register-edit-context-menu.ps1
```

如果只想检查 Edit、不创建配置：

```powershell
.\install-edit.ps1 -SkipConfig
```

## 预览和删除

先只列出待删除项目，不执行删除：

```powershell
.\remove-edit-context-menu.ps1 -ListOnly
```

确认后执行删除。PowerShell 默认会因为高影响操作请求确认：

```powershell
.\remove-edit-context-menu.ps1
```

也可以显式确认：

```powershell
.\remove-edit-context-menu.ps1 -Confirm:$true
```

## 注册内容

菜单显示为 `Use Edit`，命令为：

```text
wt.exe -w 0 new-tab --title "Use Edit" edit "%1"
```

只使用当前用户注册表，不写入 HKLM/HKCR，不替换 `.txt`、`.json` 等默认打开程序。Windows 11 精简右键菜单中可能需要点击“显示更多选项”。

## 覆盖的扩展名

`.txt`, `.json`, `.jsonc`, `.yaml`, `.yml`, `.md`, `.markdown`, `.toml`, `.ini`, `.conf`, `.env`, `.xml`, `.csv`, `.tsv`, `.log`, `.config`, `.properties`, `.sh`, `.bash`, `.zsh`, `.bat`, `.cmd`, `.ps1`, `.py`, `.js`, `.jsx`, `.ts`, `.tsx`, `.html`, `.htm`, `.css`, `.scss`, `.less`, `.sql`, `.graphql`, `.gql`, `.vue`, `.svelte`, `.rs`, `.go`, `.java`, `.c`, `.h`, `.cpp`, `.hpp`, `.cs`, `.swift`, `.kt`, `.kts`, `.lua`, `.rb`, `.php`, `.tex`, `.gitignore`, `.gitattributes`, `.dockerfile`。

注意：`.dockerfile` 只匹配以 `.dockerfile` 结尾的文件；无扩展名的 `Dockerfile` 需要单独的文件名关联，当前脚本不会添加它。
