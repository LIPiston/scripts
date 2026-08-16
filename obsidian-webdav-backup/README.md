# obsidian-webdav-backup

每天把 starxn 上 `vault-git` 仓库的**工作区文件**覆盖备份到 WebDAV；不上传 `.git`，因此不备份 Git 历史、对象和索引。

## 文件

- `backup_obsidian_webdav.sh`：备份脚本
- `.env.example`：配置模板；复制为 `.env` 后填写路径和 WebDAV 凭据

## 安装到 starxn

```bash
mkdir -p /root/bin/obsidian-webdav-backup
scp backup_obsidian_webdav.sh .env.example root@starxn:/root/bin/obsidian-webdav-backup/
ssh root@starxn
cd /root/bin/obsidian-webdav-backup
cp .env.example .env
chmod 700 backup_obsidian_webdav.sh
chmod 600 .env
vi .env
./backup_obsidian_webdav.sh
```

脚本会：

1. 使用 `find` 遍历仓库工作区；
2. 排除 `.git`；
3. 自动创建 WebDAV 目录；
4. 使用 `PUT` 上传每个文件，同名文件直接覆盖；
5. 用锁目录避免同一时间重复运行。

注意：这是“覆盖备份”，不会删除 WebDAV 上已经存在、但后来从源仓库删除的旧文件。若需要严格镜像（远端多余文件也删除），应再单独增加清理步骤，避免误删。

## 每天定时执行

例如每天 03:30：

```cron
30 3 * * * /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh >> /var/log/obsidian-webdav-backup.log 2>&1
```

## 前置检查

在 starxn 上安装并确认 `curl`：

```bash
command -v curl
```

不要把 `.env` 提交到 Git；它包含 WebDAV 密码。
