# CS2 CFG Switcher

一个纯 `.bat` 的 Windows 本地脚本，用来备份/切换当前 Steam 登录用户的 CS2 配置目录：

`C:\Program Files (x86)\Steam\userdata\<steamid>\730\local\cfg`

功能：

1. 从已登录的多个 Steam 用户中选择一个，备份该用户的 CS2 `cfg` 文件夹
2. 先选择目标 Steam 用户，再从已有备份中选择一份覆盖到该用户

## 使用方法

双击运行：

`run-cs2-cfg-switcher.bat`

也可以从命令行指定 Steam 目录：

```bat
run-cs2-cfg-switcher.bat "D:\Steam"
```

不传参数时会像 `SteamSwitcher` 一样优先从注册表自动检测 Steam 安装目录：

- `HKCU\Software\Valve\Steam` / `SteamPath`
- `HKLM\SOFTWARE\WOW6432Node\Valve\Steam` / `SteamPath` 或 `InstallPath`
- `HKLM\SOFTWARE\Valve\Steam` / `SteamPath` 或 `InstallPath`

如果自动检测失败，会再尝试：

`C:\Program Files (x86)\Steam`

## 备份位置

备份会保存在本项目目录下：

`backups\日期时间_<steamid>_<steamName>\cfg`

每份备份旁边会生成 `manifest.json`，记录来源路径、SteamID、时间等信息。

## 安全说明

- 恢复备份时，脚本会先把目标用户当前 `cfg` 自动备份到 `backups\pre-restore-*`，再覆盖；选择目标用户和备份后不再要求输入 YES。
- 如果检测到多个 Steam 用户，脚本会优先读取 `Steam\config\loginusers.vdf` 中 `MostRecent=1` 的用户；仍无法确定时会让你选择。
- 脚本不会删除你的备份。
- 脚本主体是 `run-cs2-cfg-switcher.bat`，不依赖 PowerShell。
