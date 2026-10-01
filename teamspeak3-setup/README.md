# teamspeak3-setup

在阿里云轻量应用服务器（别名 `light-aliyun`）上原生部署 TeamSpeak 3 服务端。

## 背景

需要一台自己的语音服务器（TS3 稳定版，客户端兼容性最好，免费 32 槽）。目标机同时跑着
RustDesk（hbbs/hbbr，21115-21119）和 Tailscale DERP（80/443 TCP），因此 TS3 只使用它自己的
默认端口，不碰 80/443。

## 目标环境

| 项 | 值 |
|---|---|
| 主机 | light-aliyun（阿里云轻量应用服务器，Ubuntu 22.04.5 LTS, x86_64, 2 核 / 1.6G / 40G） |
| 部署目录 | `/opt/teamspeak3`（独立目录，非 Docker） |
| 运行用户 | `teamspeak`（系统用户，nologin，目录 700/600 权限） |
| 服务管理 | systemd 单元 `teamspeak3.service`（Type=forking，Restart=always） |
| 版本 | TeamSpeak 3 Server 3.13.8（无 license = 官方免费档：1 个虚拟服务器 / 32 槽） |

## 用法

```bash
scp install_teamspeak3.sh root@<host>:/tmp/
ssh root@<host> 'TS_VER=3.13.8 bash /tmp/ts3_install.sh'   # 或对应文件名
```

脚本幂等：已存在 `/opt/teamspeak3/ts3server` 时跳过下载解包，只重写 `ts3server.ini` 和 systemd 单元并重启
（重启前会备份旧 ini 为 `ts3server.ini.bak-<时间戳>`）。

## 配置要点

`/opt/teamspeak3/ts3server.ini`（600，属 teamspeak）：

```ini
default_voice_port=9987
voice_ip=0.0.0.0
filetransfer_port=30033
filetransfer_ip=0.0.0.0
query_port=10011
query_ip=127.0.0.1            # ServerQuery 只监听本机，不暴露到公网
query_ip_allowlist=query_ip_whitelist.txt   # 仅 127.0.0.1 / ::1
query_ip_denylist=query_ip_blacklist.txt
dbplugin=ts3db_sqlite3
```

安全设计：

- ServerQuery（10011）绑定 `127.0.0.1`，且 allowlist 只放行本机，需要时用 SSH 隧道访问，
  避免把 query 端口暴露成爆破入口。
- `${BASE}/.ts3server_license_accepted` 用于免交互接受许可（等价于 `--accept-license`）。
- 目录属主 `teamspeak:teamspeak`，ini 600、logs 700，服务以非 root 运行。

## 端口

| 端口 | 协议 | 用途 | 公网放行 |
|---|---|---|---|
| 9987 | UDP | 语音 | 必须（阿里云轻量：防火墙 → 添加规则 UDP 9987） |
| 30033 | TCP | 文件传输 | 建议（图标/文件上传下载） |
| 10011 | TCP | ServerQuery | 不放行（仅本机，需要时 SSH 隧道） |
| 10022 / 10080 | TCP | SSH/HTTP query | 不放行（进程虽监听 0.0.0.0，但被 allowlist 限制为仅本机可认证） |

注意：`iptables`/`ufw` 在服务器侧默认放行（ufw inactive），**真正拦流量的是阿里云轻量应用服务器的
控制台防火墙**，必须在控制台放行，本机脚本改不了。

## 实测记录（2026-10-01）

- 安装后 `systemctl is-active teamspeak3` = active，`NRestarts=0`，内存占用约 12M（1.6G 机器无压力）。
- 服务器侧监听确认：`9987/udp 0.0.0.0`、`30033/tcp 0.0.0.0`、`10011/tcp 127.0.0.1`。
- 日志显示 `max virtualservers: 1 / max slots: 32`（无 license 的官方免费档）。
- 外网可达性用第三方 vantage（HK VPS `starxn`）实测：22 通，9987/30033/10011/10022/10080 **全部超时**
  → 说明云防火墙当时只放行了 22，需在控制台补放 9987/udp 与 30033/tcp。
  （注：本机 Windows 侧的 TCP 测试结果全为 OPEN，是 Mihomo TUN 拦截导致的假阳性，不可用于判断外网可达性。）
- 首次启动日志 `*_1.log` 内含一次性 ServerAdmin 特权密钥（`token=...`），用 TS3 客户端连接时输入即可获得
  服务器管理员身份，用后立即失效。

## 运维命令

```bash
systemctl status teamspeak3
systemctl restart teamspeak3
journalctl -u teamspeak3 -n 50            # systemd 层日志
ls -t /opt/teamspeak3/logs/ | head        # TS3 自身日志（_0 admin / _1 virtualserver）
grep -a "token=" /opt/teamspeak3/logs/ts3server_*_1.log   # 找回特权密钥
```

卸载/回滚（**执行前需确认**）：

```bash
systemctl disable --now teamspeak3
rm -f /etc/systemd/system/teamspeak3.service && systemctl daemon-reload
# 数据（含 sqlite 库与上传文件）在 /opt/teamspeak3/logs 与 /opt/teamspeak3/files，删除前先备份
```
