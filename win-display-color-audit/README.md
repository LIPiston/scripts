# win-display-color-audit

Windows 显示器色彩链路体检 + 目视校验图生成。**只用 Python 标准库**，不需要装任何东西
（ctypes + winreg + struct + zlib）。

回答三个实际问题：

1. **现在真正生效的是哪个 ICC/ICM 文件？** —— 不是"装了哪些"，而是"mscms/GDI 现在把谁交给色彩管理软件"。
2. **面板标称的色域/白点/gamma 到底是多少？** —— 从 EDID 声明 + 出厂 profile 里**内嵌的实测数据**分别推。
3. **色彩管理真的在工作吗？** —— GPU gamma ramp(vcgt)、硬件校准(MHC2)、Windows ACM/HDR 三个状态一起看。

## 用法

```bash
python display_color_audit.py            # 人类可读报告
python display_color_audit.py --json     # 结构化输出（给别的脚本吃）
python display_color_audit.py --no-scan  # 跳过扫描 spool 目录里全部 ICC，快

python gen_test_patterns.py --gen-patterns ./patterns   # 生成目视校验图
```

如果同一台机器上装了 pyenv/uv 里的多个 python，用哪个都行；没有第三方依赖。

## 它到底读了哪些"真相来源"

| 来源 | 拿到了什么 | 为什么重要 |
| --- | --- | --- |
| `Gdi32!GetICMProfileW` | 当前交给应用的 ICC 完整路径 | **唯一**能证明"现在生效的是谁"的接口（注册表只说明关联，不说明生效） |
| `Gdi32!GetDeviceGammaRamp` | 3x256 的 16bit LUT | 单位曲线 = 没有任何校准 LUT 被加载；非单位 = 有 VCGT 生效 |
| EDID（`Enum\DISPLAY\*\Device Parameters\EDID`） | 面板声明的原色/白点/尺寸/HDR 元数据 | 面板硬件能力，CPU 侧的"身份证" |
| ICC 的 `chad` + `rXYZ/gXYZ/bXYZ` | **还原后的原生原色**（D50 PCS 适配前的值） | 很多"标称 profile"存的是标准值，还原后才看得出它是不是真·实测 |
| ICC 内嵌 `CxF `（X-Rite Prism ZXML） | 逐台实测的 XYZ 白点/亮度/原色 + 生成时间 | **区分"实测 profile"和"套用标准值的 profile"的唯一硬证据** |
| `HKLM\SYSTEM\...\GraphicsDrivers\MonitorDataStore` | `AutoColorManagementEnabled` / `HDREnabled` / `SDRWhiteLevel` | ACM 是否在替所有应用做 sRGB 收敛 |
| `HKCU\...\ICM\ProfileAssociations\Display` + `HKLM` 同名键 | 系统级 / 用户级关联 | 判断是不是"每用户覆盖了系统默认" |

## 报告怎么读（判据）

- `► 交给色彩管理应用用的 ICC` 才是当前生效的。显示 `(无 → 按 sRGB 处理)` 在 ACM 打开时是**正常**的（ACM 规范要求 WCS 返回空 profile）。
- `ACM 支持=1 且 ACM 已启用=0` → Windows 不会替非色彩管理程序收敛色域，DCI-P3 屏会**全局偏艳**。
- `gamma ramp 单位曲线` → 没有加载任何校准 LUT（即使你刚用校色仪生成过 profile，也说明它没被加载）。
- profile 表里带 `CxF 236块 @日期` 的才是**逐台实测**的；不带的就是标称套用标准色域的。
- 原色一栏是**还原后的原生值**；如果某文件的图元与某标准差 <0.001，那它是"标称"文件。

## 目视校验（没有校色仪时的替代方案）

`gen_test_patterns.py` 生成 5 张**未打标记的 sRGB 数值图**，关键玩法是**拿一台你信任的设备并排比**
（手机通常把 sRGB 内容正确收敛到 sRGB），而不是只看这一块屏：

| 图 | 看什么 | 异常表现 |
| --- | --- | --- |
| `01_gray_ramp.png` | 连续灰阶 + 11 级阶梯 | 出现色带/断阶 → 8bit 不够或 LUT 过陡 |
| `02_near_black.png` | 0..16 的 8bit 块 | 0 与 1..4 全一样黑 → 黑位被抬高/暗部被压 |
| `03_near_white.png` | 240..255 | 240..255 并成一片 → 高光被削平 |
| `04_primaries.png` | 原色/补色 + 25/50/75/100% 灰 | 灰阶偏冷偏暖 → 白点没被管理 |
| `05_wide_gamut_probe.png` | sRGB 里"到顶"的橙/红/黄 | 比手机明显更艳更炸 → 典型的广色域过饱和 |

**软件能查"配置对不对"，查不了"颜色准不准"。** 想看真实的 ΔE / 实际色域，只有校色仪
（Calibrite Display / SpyderX + DisplayCAL）能给出权威数字。

## 已知坑

- `MonitorDataStore` 里的 `SDRWhiteLevel` 是"每档基准 nits × 10"的 10bit 指数，不是 nits：
  1000 → 100 nits（标准 sRGB 参考白），625 → 80 nits。别当成亮度值读。
- `WcsGetDefaultColorProfile` 在部分显示器上永远返回 false（本机就是），因为它读的是**不带 `\\?\` 前缀**
  的设备路径。**以 `GetICMProfileW` 的结果为准**。
- 某些 OEM profile 的 `vcgt` 的 count/channels 字段被写反、甚至整体小端存储。脚本会两种布局都试，
  只在曲线单调且形状合理时才认；否则明确输出 `layout_recognized: false`，**不猜**。
- `spool\drivers\color` 的 `CreationTime` 会被"复制覆盖"刷新，**不要用它判断新旧**；要看 profile
  内嵌 CxF 的 `CreationDate` 和文件的 `LastWriteTime`。
- 目录里可能同时存在 `.icm`(Windows 生成，带 MHC2) 和 `.icc`(标称，纯矩阵)：两者用途不同，别混用。
- 有第三方"控制中心"类软件会自己往 spool 写 profile 并改 `HKCU\...\ProfileAssociations`（本机是
  OpenRevo 的 `color_calibration.json`）。手工设置和它会互相覆盖，排查时先确认谁在写。

## 限制

- 不读显示器内部 OSD 状态，也不做任何写入：**只读**。脚本不会改注册表、不会装 profile。
- 不做真实色度计算（需要分光/色度计），EDID/实测数据的推算是解析，不是测量。
