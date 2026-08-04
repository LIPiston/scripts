# Zed 经典右键菜单修复工具

用于解决 Windows 11 关闭初级菜单/新版右键菜单后，Zed 的「用 Zed 打开」只在初级菜单里注册、经典 Win10 风格菜单里丢失的问题。

这个工具会读取当前注册表里已有的右键菜单候选项，并允许选择把有普通 `command` 的项目复制到经典二级菜单；同时内置了 Zed 的一键修复，会自动检测 Zed i18n / Zed 的安装路径并写入经典菜单。

## 推荐用法

双击：

```text
run-zed-classic-context-menu.bat
```

然后选择：

```text
[A] 自动把 Zed 放进经典二级菜单（推荐）
```

或者直接在 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\zed-classic-context-menu.ps1 -InstallZed
```

如果自动检测不到 Zed：

```powershell
.\zed-classic-context-menu.ps1 -InstallZed -ZedExe "$env:LOCALAPPDATA\Programs\Zed i18n\Zed.exe"
```

## 写入内容

只写当前用户注册表，不需要管理员权限：

```text
HKCU\Software\Classes\*\shell\ZedClassicOpenFile
HKCU\Software\Classes\Directory\shell\ZedClassicOpenFolder
HKCU\Software\Classes\Directory\Background\shell\ZedClassicOpenHere
```

对应命令：

```text
"Zed.exe" "%1"   # 文件 / 文件夹
"Zed.exe" "%V"   # 文件夹空白处
```

## 读取/选择其它菜单项

交互菜单里的：

```text
[L] 读取并列出当前右键菜单候选项
[C] 从候选项中选择一个有 command 的项目复制到经典菜单
```

说明：

- 普通 `shell\...\command` 项可以复制。
- 只有 `ExplorerCommandHandler` 的 Win11 初级菜单项通常不能直接复制到经典菜单，因为它不是普通命令行；Zed 推荐用内置一键修复补一个普通 command。

## 卸载

交互菜单选择 `[R]`，或运行：

```powershell
.\zed-classic-context-menu.ps1 -RemoveZed
```

## 非交互参数

```powershell
.\zed-classic-context-menu.ps1 -ListOnly
.\zed-classic-context-menu.ps1 -InstallZed
.\zed-classic-context-menu.ps1 -RemoveZed
```
