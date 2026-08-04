# Zed 经典右键菜单修复工具

用于解决 Windows 11 关闭初级菜单/新版右键菜单后，Zed 的「用 Zed 打开」只在一级菜单里注册、经典 Win10 风格二级菜单（「显示更多选项」）里丢失的问题。

这个工具的核心流程是：

1. 列出当前可读到的一级右键菜单内容。
2. 让用户选择要放到二级/经典菜单的项目。
3. 对有普通 `command` 的项目自动复制到二级菜单。
4. 对只有 `ExplorerCommandHandler` / COM handler 的项目只列出并说明不可直接复制。
5. 提供删除本工具创建的二级菜单项。

同时内置 Zed 一键修复，会自动检测 Zed i18n / Zed 的安装路径并补一个普通 command。

## 推荐用法

双击：

```text
run-zed-classic-context-menu.bat
```

主菜单：

```text
[A] 自动把 Zed 放进经典二级菜单（推荐）
[L] 列出所有一级菜单候选项
[C] 选择一级菜单项，放入二级/经典菜单
[D] 删除本工具创建的二级/经典菜单项
[R] 删除本工具创建的 Zed 经典菜单
[Q] 退出
```

## 直接安装 Zed 二级菜单

```powershell
cd D:\LIPis\Documents\code\scripts\zed-classic-context-menu
Set-ExecutionPolicy -Scope Process Bypass -Force
.\zed-classic-context-menu.ps1 -InstallZed
```

如果自动检测不到 Zed：

```powershell
.\zed-classic-context-menu.ps1 -InstallZed -ZedExe "$env:LOCALAPPDATA\Programs\Zed i18n\Zed.exe"
```

## Zed 写入内容

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

## 读取/选择一级菜单

交互菜单里的 `[L]` 会列出可读到的一级菜单候选项，包括：

- 普通 `shell\...\command` 菜单项：标记为「可复制」。
- `shellex\ContextMenuHandlers` 菜单项：标记为「不可直接复制」。
- `ExplorerCommandHandler` / PackagedCom 现代菜单项：标记为「不可直接复制」。

选择 `[C]` 后输入编号：

- 如果该项有普通 `command`，工具会复制到对应的二级/经典菜单位置。
- 如果该项只有 COM handler，工具会拒绝迁移并解释原因，避免写出坏菜单。

## 删除二级菜单

删除所有由本工具创建的二级/经典菜单项：

```powershell
.\zed-classic-context-menu.ps1 -RemoveCreated
```

只删除 Zed 内置修复创建的三项：

```powershell
.\zed-classic-context-menu.ps1 -RemoveZed
```

交互菜单也提供：

```text
[D] 删除本工具创建的二级/经典菜单项
[R] 删除本工具创建的 Zed 经典菜单
```

## 非交互参数

```powershell
.\zed-classic-context-menu.ps1 -ListOnly
.\zed-classic-context-menu.ps1 -CopyId 12
.\zed-classic-context-menu.ps1 -InstallZed
.\zed-classic-context-menu.ps1 -RemoveZed
.\zed-classic-context-menu.ps1 -RemoveCreated
```
