# Windows 11 服务精简（游戏优先 + 保 WSL2）

2026-09-28 在本机（YILONG / Ryzen 7 H 255 / RTX 5060 Laptop / 16GB / Win11 25H2 build 26200）实测执行的方案。
目标：在不破坏 **WSL2**、**外设（Xbox 手柄/蓝牙）**、**远程工具（Tailscale/RustDesk/sshd）**、**杀软（火绒）** 的前提下，砍掉遥测和无用服务。

## 文件

| 文件 | 用途 |
|---|---|
| `disable-services.ps1` | 精简脚本（自动提权、逐项回读、生成回滚脚本、校验保留清单）。2026-10-05 修订：已把诊断链移出禁用清单；已禁用的收件箱默认服务会被跳过并标注而非计为收益 |
| `restore-diagnostic-chain.ps1` | **2026-10-05 修复脚本**：把 `DPS` / `WdiServiceHost` / `WdiSystemHost` 恢复到 Windows 默认的「手动（按需）」，修好空白的电池使用图表 |
| `rollback.ps1` | 本机当前状态对应的精确回滚（只把启动类型改回去，不删服务） |
| `wslconfig-game-first.txt` | `.wslconfig` 模板：把 WSL2 的内存让给游戏 |

## 2026-10-05 发现的破坏：电池使用图表变空

**症状**：设置 → 系统 → 电源和电池 里的「电池使用情况」24 小时图变成空白。

**原因**：2026-09-28 那批把 `DPS`（Diagnostic Policy Service）、`WdiServiceHost`、
`WdiSystemHost` 一起禁掉了。这三条是 SRUM / 能源估算引擎（E3）的能耗归因上下文，
图的数据就来自它；连同 `powercfg /energy`、`sleepstudy`、WDI 的 ETL 跟踪也一起废掉。

**证据**（System 日志，服务控制管理器 7040）：
```
2026-09-28 23:21:34  Diagnostic Policy Service   自动启动 → 已禁用
2026-09-28 23:21:34  Diagnostic Service Host     按需启动 → 已禁用
2026-09-28 23:21:35  Diagnostic System Host      按需启动 → 已禁用
```

**修复**：管理员运行 `restore-diagnostic-chain.ps1`，然后重启。三者恢复为「手动」，
仍然不会随开机自启，省资源的效果基本保留。运行后重启的验证方法：拔掉电源用一会儿电池，
再打开 设置 → 电源和电池 看 24 小时图是否重新出现。

**教训**：这三条是 `$NeverDisable` 清单里的，`disable-services.ps1` 现在会在清单自相矛盾时直接报错退出。

### 另一条更正：那 22 项里大部分本来就是禁用的

最初报告「禁用 22 项」有误。`DiagTrack`/`DusmSvc`/`InventorySvc`/`WSAIFabricSvc`/
`MapsBroker`/`smphost`/`TieringEngineService`/`RetailDemo` 等在 Windows 首次开机（OOBE）阶段
就已经是 `Start=4` + `State=1223`（从未启动），属于出厂默认值。把它们「禁用」一次并不省任何资源；
真正被削减的是**当时处于运行状态**的那些（`Print Spooler`、`WdiServiceHost`、
`WdiSystemHost`、`whesvc` 等）。脚本现在会跳过已禁用的项并在报告里注明 `already disabled - no saving`。

## 禁用清理（Start=4）

```
DiagTrack            dmwappushservice   WSAIFabricSvc      InventorySvc
DusmSvc              MapsBroker         WMPNetworkSvc      PhoneSvc
SEMgrSvc             SmsRouter          WalletService      workfolderssvc
RetailDemo           smphost            TieringEngineService  ALG
AxInstSV             lfsvc              TrkWks
```

（`DPS` `WdiServiceHost` `WdiSystemHost` 已于 2026-10-05 移出此清单，见上。）

改为手动（不发车但不禁用）：`BITS`、`WSearch`

### 批次 B（同日第二批，8 项禁用）

```
Spooler            StiSvc             MRAfterSaleService   NahimicService
AMD Crash Defender Service             webthreatdefsvc      whesvc
seclogon
```
另外把 per-user 服务的**模板** `webthreatdefusersvc` 置为 Disabled（实例
`webthreatdefusersvc_1537d7` 由模板在登录时创建，禁用模板即可；实例本身拒绝直接改配置，sc 报错 87）。

两个已知的"改不动"要记住：

| 服务 | 现象 | 处理 |
|---|---|---|
| `webthreatdefusersvc_*`（per-user 实例） | `Set-Service`/`sc config` 报"参数错误"(87)，`Win32_Service` 甚至不枚举它 | 改**模板** `sc.exe config webthreatdefusersvc start= disabled`；实例当前已 Stop，下次登录不会再被拉起 |
| `seclogon` | `sc query` 显示 `NOT_STOPPABLE`，`Stop-Service` 失败 | 只改启动类型（Disabled），本进程会一直运行到下次重启，重启后不再启动 |

## 绝不要动（保 WSL2 与游戏体验）

| 类别 | 服务 | 原因 |
|---|---|---|
| WSL2 | `WSLService` `WslInstaller` `vmcompute` `hns` `HvHost` | WSL 启动、按需拉起的 Hyper-V 主机计算服务、主机网络服务。`hypervisorlaunchtype` 保持 `auto`（`HypervisorPresent=True`），关掉会连 VMware/雷电一起废 |
| 蓝牙/手柄 | `bthserv` `BTAGService` `BthAvctpSvc` `MTKBTSVC` `GameInputSvc` `GameInputRedistService` `XboxGipSvc` `hidserv` | 已配对 Xbox Wireless Controller |
| 显卡 | `AMD External Events Utility`（FreeSync/VRR）、`AmdPpkgSvc` `amdpmfservice`、`NVDisplay.ContainerLocalSystem` `nvagent` | 掉帧/功能丢失 |
| 安全 | `HipsDaemon` `HRWSCCtrl`（火绒）、`mpssvc` `BFE` | Defender 已被火绒接管，别关火绒 |
| 远程/自用 | `sshd` `ssh-agent` `Tailscale` `RustDesk` | 用户在用 |
| 按需保留 | `WbioSrvc`（Windows Hello 人脸，用户可能要用）、`NcdAutoSetup`（手机 USB 网络共享）、`SharedAccess`（移动热点）、`SSDPSRV` `fdPHost` `FDResPub`（局域网发现）、`GameViewerService`（远程协助他人） | 用户明确要求保留 |

## 回滚

管理员运行 `rollback.ps1`，或单条：

```powershell
Set-Service -Name <服务名> -StartupType Automatic   # 或 Manual
```

`Win32_Service.StartMode` 的取值是 `Auto`/`Manual`/`Disabled`，而 `Set-Service -StartupType` 只认
`Automatic`/`Manual`/`Disabled`，转换时别弄错。

## 坑

- **`.ps1` 必须是纯 ASCII**（或带 UTF-8 BOM）：PowerShell 5.1 读无 BOM 的脚本时按 ANSI/GBK 解码，
  中文注释会被拆成乱码字节，某些字节对会吞掉行尾，导致**下一行被注释掉**（本例吞掉了
  `$manual = @('BITS','WSearch')`，静默漏改两个服务）。
- 改服务启动类型需要管理员；用 `Start-Process -Verb RunAs -Wait` 提权会弹 UAC，需要人点一下。
- `Set-Service ... -StartupType Disabled` 前先 `Stop-Service`，否则运行中的服务会报错。
- **不要动诊断链** `DPS` / `WdiServiceHost` / `WdiSystemHost`：它们是能源估算（E3/SRUM）的
  服务上下文，禁掉会让「电池使用情况」图表变空，还会一起废掉 `powercfg /energy`、
  `sleepstudy` 和 WDI 的 ETL 跟踪。这三条本来就是「手动（按需）」，禁掉换不到资源
  （见上「2026-10-05 发现的破坏」）。
- **判断某个服务值不值得禁，看它现在是否在跑**，而不是看它叫什么名字：Windows 里有大量
  收件箱默认的 `Start=4` + `State=1223` 项，禁用它们等于什么也没做。
- `disable-services.ps1` 的 `-WhatIf` **不会**把开关传给提权后的子进程；只想预演时不要用它
  （脚本检测到 `-WhatIf` 就不再提权，直接在无管理员权限下打印结果）。
