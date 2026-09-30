# laptop-battery-recorder

独立的 Windows 笔记本续航数据记录工具。它不运行固定压力测试，而是启动 HWiNFO 后让用户正常使用电脑，收集真实场景数据。

## 运行

双击：

```text
记录续航数据.bat
```

首次运行会在本工具目录创建 `venv` 并安装 `psutil`，之后复用该环境。

也可以手动运行：

```bat
venv\Scripts\python.exe record_battery_session.py
```

## 记录内容

- HWiNFO 传感器 CSV，默认轮询间隔 2000 ms
- Windows 电池电量
- 是否接通电源
- Windows 估计剩余时间
- 带时区时间戳
- 会话摘要 JSON

默认 HWiNFO 路径：

```text
D:\Program Files\TubaWinUi3\Tools\综合检测\hwinfo\HWiNFO64.exe
```

## 输出

每次运行在 `output` 目录生成：

```text
hwinfo_YYYYMMDD_HHMMSS.csv
windows_battery_YYYYMMDD_HHMMSS.csv
battery_summary_YYYYMMDD_HHMMSS.json
```

记录时可以正常办公、浏览网页、看视频、编程、待机和插拔电源。按 `Ctrl+C` 停止并生成摘要。

## 自动休眠

默认在电池供电且电量达到 10% 或更低时调用 Windows 休眠接口：

```bat
记录续航数据.bat --no-auto-sleep
记录续航数据.bat --sleep-threshold 8
```

HWiNFO 需要管理员权限或命令行自动日志授权时，请以管理员身份运行批处理；如果 HWiNFO 启动失败，Windows 电池记录仍会继续。

## 设计说明

单个场景不会被伪装成“完整续航”。多次记录后，可以根据真实场景的电量下降速度、插电状态和 HWiNFO 功耗字段进行综合统计。
