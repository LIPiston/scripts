# starxn-derper-cert-sync

把 1Panel 管理的 `derper.lipiston.eu.org` 证书自动分发进 starxn 上的 `tailscale-derper` 容器，并刷新 OpenResty 的 443 入口。

当前生效的部署方式：**1Panel 负责签发/续期，systemd timer 负责分发**（脚本 `derper-cert-sync.sh`）。

## 为什么需要它

DERP 的链路是两跳，两跳各用一份证书：

```text
客户端 --TLS--> derper.lipiston.eu.org:443 -- OpenResty --TLS--> 127.0.0.1:33445 (容器 tailscale-derper)
```

- OpenResty 用 `/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/{fullchain.pem,privkey.pem}`（1Panel 管理，续期时就地覆盖）。
- 容器需要自己目录下的 `data/derper.lipiston.eu.org.{crt,key}`；容器把宿主机的 `data` 目录以只读方式挂到 `/app/certs`，所以**不能用符号链接**指到 1Panel 证书目录（容器内会看到链接但看不到目标），只能复制。
- OpenResty 启动时把证书读进内存，**换文件后必须 reload**，否则客户端看到的还是旧证书。

少了任何一步，就会出现“1Panel 明明续期了、DERP 还报证书过期”。2026-10-03 就是这么挂的：`lipiston.eu.org` 通配符证书 2026-09-30 03:02 UTC 到期，DERP 全部走 relay 失败。

## 组成与路径

| 角色 | 路径 |
|---|---|
| 脚本 | `/opt/derper-cert-sync/derper-cert-sync.sh` |
| 兼容软链 | `/usr/local/bin/derper-cert-sync.sh` -> 上面那个 |
| systemd | `/etc/systemd/system/derper-cert-sync.service` + `.timer` |
| 触发 | 开机后 2 分钟 + 每 15 分钟（`OnBootSec=2min`、`OnUnitActiveSec=15min`、`Persistent=true`） |
| 日志 | `/var/log/derper-cert-sync.log` |
| 源（1Panel） | `/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/{fullchain.pem,privkey.pem}` |
| 目标（容器） | `/opt/1panel/docker/compose/tailscale-derper/data/derper.lipiston.eu.org.{crt,key}` |

## 一轮同步做什么

1. 读 1Panel 的源证书；两道校验：必须覆盖 `derper.lipiston.eu.org`（`openssl -checkhost`）、剩余有效期 > 3 天（`-checkend 259200`）。不通过只写 `ERROR` 进日志，**什么都不动**。
2. 比较 `sha256(源 fullchain.pem)` 与 `sha256(data/derper.lipiston.eu.org.crt)`：
   - 相同 -> 直接 `exit 0`，静默结束，**不重启任何东西**（所以 15 分钟一轮几乎没有代价）。
   - 不同 -> 覆盖 `.crt`(644)/`.key`(600) -> `docker restart tailscale-derper` -> `openresty -s reload` -> 写一行日志。
3. OpenResty 容器名运行时用 `docker ps` 自己找（不硬编码）；找不到或 reload 失败会写 `ERROR: ... port 443 still serves the previous cert`。

设计取舍：只在内容变化时重启，是因为 derper 重启会让 relay 连接断几秒（客户端会自动重连或转直连），没必要每 15 分钟来一次。

## 安装 / 重装到 starxn

```bash
# 1) 脚本
ssh starxn 'mkdir -p /opt/derper-cert-sync'
scp derper-cert-sync.sh starxn:/opt/derper-cert-sync/derper-cert-sync.sh
ssh starxn 'chmod 755 /opt/derper-cert-sync/derper-cert-sync.sh'

# 2) systemd
scp derper-cert-sync.service derper-cert-sync.timer starxn:/etc/systemd/system/
ssh starxn 'systemctl daemon-reload && systemctl enable --now derper-cert-sync.timer && systemctl start derper-cert-sync.service'

# 3) 兼容软链（可选，方便直接敲脚本名）
ssh starxn 'ln -sf /opt/derper-cert-sync/derper-cert-sync.sh /usr/local/bin/derper-cert-sync.sh'
```

## 常用命令

```bash
# 手工触发一次
ssh starxn 'systemctl start derper-cert-sync.service'

# 看日志 / 看 systemd 侧
ssh starxn 'tail -n 20 /var/log/derper-cert-sync.log; journalctl -u derper-cert-sync.service -n 20 --no-pager'

# 改频率（编辑 .timer 的 OnUnitActiveSec 后）
ssh starxn 'systemctl daemon-reload && systemctl restart derper-cert-sync.timer && systemctl list-timers derper-cert-sync.timer'
```

## 验证

```bash
# 1) 两侧证书到期时间应一致
ssh starxn 'openssl x509 -in /opt/1panel/docker/compose/tailscale-derper/data/derper.lipiston.eu.org.crt -noout -enddate; \
            openssl x509 -in /opt/1panel/www/sites/derper.lipiston.eu.org/ssl/fullchain.pem -noout -enddate'

# 2) 客户端实际看到的（443 入口，OpenResty 呈现的）
ssh starxn 'echo | openssl s_client -connect derper.lipiston.eu.org:443 -servername derper.lipiston.eu.org 2>/dev/null | openssl x509 -noout -subject -dates'

# 3) 连通性：期望 200
ssh starxn 'curl -sS -o /dev/null -w "%{http_code}\n" https://derper.lipiston.eu.org/derp/probe'

# 4) tailscaled 侧：期望看到 derp-900 connected
ssh starxn 'journalctl -u tailscaled --since "5 min ago" --no-pager | grep -i derp'
```

端到端演练（安全、可重复）：把 `data/` 里的证书换成另一份旧证书，跑一次脚本，看是否被自动纠正并 reload：

```bash
ssh starxn 'D=/opt/1panel/docker/compose/tailscale-derper/data; \
  cp -a "$D/lipiston.eu.org.crt" "$D/derper.lipiston.eu.org.crt"; \
  /opt/derper-cert-sync/derper-cert-sync.sh; tail -2 /var/log/derper-cert-sync.log'
```

## 回滚

脚本自身不建备份目录；改动前建议手工留一份：

```bash
ssh starxn 'D=/opt/1panel/docker/compose/tailscale-derper/data; \
  cp -a "$D/derper.lipiston.eu.org.crt" "$D/derper.lipiston.eu.org.crt.bak.$(date +%s)"'
```

历史上手工备份位置：`/root/derper.crt.backup.<epoch>`、`data/cert-sync-backups/YYYYMMDD-HHMMSS/`（2026-09-16 那次）。

## 注意：1Panel 里还有一个重叠的计划任务

1Panel 中存在名为 `derper证书` 的 **Shell 计划任务**，周期 `30 5 * * *`（每天 05:30），执行的是本仓库里那份旧脚本（`sync_derper_cert.sh` 的内容）。它和 systemd timer **功能重叠**，而且比新脚本弱：

- 不校验有效期：2026-10-03 05:30 那次它照旧把**已过期的**通配符证书（`notAfter Sep 30 03:02:09 2026`）复制进容器并重启 DERP，日志里还写着“健康检查通过 -> 204”（OpenResty 返回 204 并不能证明证书链没问题，这是误报）；
- 每次运行都重启容器（即使内容没变）；
- 没有 OpenResty reload 这一步 —— 也就是 2026-10-03 故障里缺失的那一环。

建议二选一（在 1Panel 面板里改：1Panel -> 计划任务 -> derper证书）：

1. 把命令改成 `bash /opt/derper-cert-sync/derper-cert-sync.sh`（幂等：没变化就秒退），保留这层冗余；
2. 或者直接停用/删除该任务，交给 systemd timer（每 15 分钟一次，且有哈希跳过与两道校验）。

## 历史

- `sync_derper_cert.sh`：2026-09-16 版（复制 + 校验 + 每次重启，带 `--dry-run`、备份目录、锁目录）。**已废弃**，保留作参考；服务器上仍以 1Panel 计划任务的形式运行（见上一节）。
- `derper-cert-reload.sh`（`/root/derper-cert-reload.sh`）：更早的 acme.sh 续期钩子方案，在 1Panel 接管签发后已退役为占位说明。

## 故障记录

- 2026-09-30 03:02 UTC：`lipiston.eu.org` 通配符证书过期（OpenResty 与 derper 共用），DERP 全挂；`tailscale netcheck` 只测 STUN，表现为“能连但坏”，容易误判。
- 2026-10-03：改用 1Panel 新签的 `derper.lipiston.eu.org` 证书（notAfter 2027-01-01）；补上 OpenResty reload 与哈希跳过逻辑，收敛成现在这份脚本 + systemd timer。
