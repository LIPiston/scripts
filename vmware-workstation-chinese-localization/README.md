# VMware Workstation 中文界面安装脚本

将 VMware Workstation 的中文语言文件安装到当前 Windows 用户，并启用 `zh_CN` 界面语言。

语言文件来自：

https://github.com/Kuroba-Sayuki/VMware-Workstation-Chinese-Localization

该仓库声明没有开源许可证，文件仅供学习和存档使用。此项目不把 DLL 语言文件重新分发到脚本仓库，而是运行脚本时从原仓库的 GitHub Raw 地址下载。

## 使用方法

双击：

```text
install-vmware-zh_CN.bat
```

由于 VMware 安装在 `C:\Program Files`，脚本会自动请求管理员权限。确认 UAC 后，脚本会：

1. 检查 VMware Workstation 是否安装在默认路径。
2. 从原仓库下载三个中文文件：
   - `vmappsdk-zh_CN.dll`
   - `vmui-zh_CN.dll`
   - `vmware.vmsg`
3. 将它们放到：

```text
C:\Program Files\VMware\VMware Workstation\messages\zh_CN
```

4. 修改：

```text
%APPDATA%\VMware\preferences.ini
```

加入或更新：

```ini
pref.locale = "zh_CN"
```

5. 修改前自动备份为：

```text
%APPDATA%\VMware\preferences.ini.bak-before-zh_CN
```

## 注意事项

- 运行前必须完全退出 VMware Workstation。
- 如果 `messages\zh_CN` 已存在，脚本会拒绝覆盖，不会删除或覆盖已有文件。
- 该语言包来自 VMware Workstation 17.6.4；新版新增界面可能仍显示英文。
- 如果 VMware 安装在非默认路径，需要先编辑脚本中的 `VMWARE_DIR`。
- 也可以使用 VMware 快捷方式参数 `--locale zh_CN`，但本脚本采用用户配置文件方式。
