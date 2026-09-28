# Windows 11 服务精简（游戏优先 + 保 WSL2）

2026-09-28 在本机（YILONG / Ryzen 7 H 255 / RTX 5060 Laptop / 16GB / Win11 25H2 build 26200）实测执行的方案。
目标：在不破坏 **WSL2**、**外设（Xbox 手柄/蓝牙）**、**远程工具（Tailscale/RustDesk/sshd）**、**杀软（火绒）** 的前提下，砍掉遥测和无用服务。

## 文件

| 文件 | 用途 |
|---|---|
| `disable-services.ps1` | 精简脚本（自动提权、逐项回读、生成回滚脚本、校验保留清单） |
| `rollback.ps1` | 本机当前状态对应的精确回滚（只把启动类型改回去，不删服务） |
| `wslconfig-game-first.txt` | `.wslconfig` 模板：把 WSL2 的内存让给游戏 |

## 禁用清单（Start=4，共 22 项）

```
DiagTrack            dmwappushservice   WSAIFabricSvc      InventorySvc
DusmSvc              MapsBroker         WMPNetworkSvc      PhoneSvc
SEMgrSvc             SmsRouter          WalletService      workfolderssvc
RetailDemo           smphost            TieringEngineService  ALG
AxInstSV             DPS                WdiServiceHost     WdiSystemHost
lfsvc                TrkWks
```

改为手动（不发车但不禁用）：`BITS`、`WSearch`

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
- 禁用 `DPS` 会连带废掉 `WdiServiceHost`/`WdiSystemHost`（诊断链），要一起处理。
