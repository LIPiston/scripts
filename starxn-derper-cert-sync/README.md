# starxn-derper-cert-sync

将 1Panel 管理的 DERP 证书同步到 starxn 上 `tailscale-derper` 的 Docker Compose `data` 目录。

## 为什么需要这个脚本

starxn 的 DERP 容器把宿主机目录：

```text
/opt/1panel/docker/compose/tailscale-derper/data
```

以只读方式挂载到容器 `/app/certs`。宿主机 `data` 内的符号链接不能指向挂载目录外部的 1Panel 证书目录，否则容器内会看见链接，但看不到链接目标。

本脚本采用安全的“复制 + 校验 + 重启”方式，不使用符号链接：

```text
1Panel fullchain.pem  -> data/derper.lipiston.eu.org.crt
1Panel privkey.pem    -> data/derper.lipiston.eu.org.key
```

每次正式运行都会同步两个证书文件并重启 DERP 容器，不根据文件内容变化跳过重启。

## 默认路径

```text
来源证书：/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/fullchain.pem
来源私钥：/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/privkey.pem
目标目录：/opt/1panel/docker/compose/tailscale-derper/data
Compose： /opt/1panel/docker/compose/tailscale-derper
容器：    tailscale-derper
服务：    derper
```

## 安装到 starxn

在本地仓库目录执行：

```bash
scp sync_derper_cert.sh starxn:/root/sync_derper_cert.sh
ssh starxn 'chmod 700 /root/sync_derper_cert.sh'
```

也可以通过 1Panel 文件管理器上传到 `/root/sync_derper_cert.sh`，然后设置可执行权限。

## 第一次运行：预览

```bash
bash /root/sync_derper_cert.sh --dry-run
```

`--dry-run` 会检查来源证书、SAN、目标文件变化和 Docker 环境，但不会修改文件、创建备份或重启容器。

## 正式运行

```bash
bash /root/sync_derper_cert.sh
```

脚本执行时会：

1. 检查 root、Docker、OpenSSL、来源证书和 DERP Compose 目录；
2. 验证证书 SAN 覆盖 `derper.lipiston.eu.org`；
3. 比较并记录来源和目标文件是否变化；
4. 无论是否变化，都在 `data/cert-sync-backups/<时间戳>/` 保存旧文件；
5. 使用临时文件和原子替换更新两个目标文件；
6. 校验来源与目标 SHA-256 一致；
7. 每次正式运行都重启 `derper` Compose 服务；
8. 从容器内验证证书可读且可解析；
9. 检查公网 `https://derper.lipiston.eu.org/generate_204` 返回 `204`。

## 1Panel 每周计划任务

建议在 1Panel 中创建 Shell 计划任务：

```bash
bash /root/sync_derper_cert.sh
```

周期可设置为每周一次。证书续期后，脚本会在下一次运行时发现文件变化，自动同步并重启 DERP。

更稳妥的做法是：让脚本运行在 1Panel 证书续期之后。如果 1Panel 的证书任务和本脚本在同一时间运行，可能出现竞态，建议错开至少 10 分钟。

## 配置参数

不需要修改脚本即可通过环境变量覆盖路径：

```bash
DERP_COMPOSE_DIR=/opt/1panel/docker/compose/tailscale-derper \
SOURCE_CERT=/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/fullchain.pem \
SOURCE_KEY=/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/privkey.pem \
  bash /root/sync_derper_cert.sh --dry-run
```

主要变量：

| 变量 | 默认值 |
|---|---|
| `DERP_COMPOSE_DIR` | `/opt/1panel/docker/compose/tailscale-derper` |
| `DERP_SERVICE` | `derper` |
| `DERP_CONTAINER` | `tailscale-derper` |
| `SOURCE_CERT` | `/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/fullchain.pem` |
| `SOURCE_KEY` | `/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/privkey.pem` |
| `DERP_DATA_DIR` | `$DERP_COMPOSE_DIR/data` |
| `BACKUP_DIR` | `$DERP_DATA_DIR/cert-sync-backups` |
| `DERP_DOMAIN` | `derper.lipiston.eu.org` |

## 回滚

每次实际更新前，旧文件会保存到：

```text
/opt/1panel/docker/compose/tailscale-derper/data/cert-sync-backups/YYYYMMDD-HHMMSS/
```

回滚示例：

```bash
cd /opt/1panel/docker/compose/tailscale-derper

docker compose stop derper
cp -a data/cert-sync-backups/YYYYMMDD-HHMMSS/derper.lipiston.eu.org.crt data/
cp -a data/cert-sync-backups/YYYYMMDD-HHMMSS/derper.lipiston.eu.org.key data/
chmod 644 data/derper.lipiston.eu.org.crt
chmod 600 data/derper.lipiston.eu.org.key
docker compose up -d derper
```

回滚后检查：

```bash
docker inspect tailscale-derper --format '{{.State.Status}}'
curl -4 -skS -o /dev/null -w '%{http_code}\n' https://derper.lipiston.eu.org/generate_204
```

## 安全设计

- 不删除历史备份；
- 不使用符号链接；
- 只修改两个明确的证书文件；
- 不修改 Compose 文件、OpenResty 配置或 1Panel 配置；
- 私钥目标权限保持为 `0600`；
- 使用锁目录避免计划任务重叠；
- 使用临时文件后原子替换；
- 更新后从容器内部验证，而不是只检查宿主机；
- 健康检查失败时返回非零状态，便于 1Panel 记录失败。
