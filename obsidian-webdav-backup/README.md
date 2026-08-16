# obsidian-webdav-backup

每天把 starxn 上 `vault-git` 仓库的工作区文件覆盖备份到 WebDAV；不上传 `.git`，因此不备份 Git 历史、对象和索引。

## Gitea 验证流程

脚本现在会在备份前：

1. 使用 `GIT_USERNAME` / `GIT_PASSWORD` 调用 Gitea 的 `git ls-remote` 验证账号密码；
2. 默认执行 `git pull --ff-only` 拉取 Gitea 最新内容；
3. 拉取失败或认证失败时立即停止，不上传旧内容；
4. `GIT_TERMINAL_PROMPT=0` 防止 cron 因等待密码而卡住。

使用 Gitea 的 **HTTPS Clone URL**，例如：

```bash
GIT_REMOTE="https://gitea.example.com/用户名/vault-git.git"
GIT_USERNAME="你的Gitea用户名"
GIT_PASSWORD="你的Gitea密码或Access Token"
GIT_PULL="true"
```

如果 Gitea 禁止使用账户密码进行 Git HTTPS 认证，请在 Gitea 生成 Access Token，把 Token 填入 `GIT_PASSWORD`。

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

必须填写：

```bash
VAULT_GIT_DIR="/root/data/vault-git"
GIT_REMOTE="https://gitea.example.com/用户名/vault-git.git"
GIT_USERNAME="你的用户名"
GIT_PASSWORD="你的密码或Token"
GIT_PULL="true"
```

WebDAV 配置仍然需要填写：

```bash
WEBDAV_URL="https://你的-webdav地址"
WEBDAV_REMOTE_DIR="obsidian-vault"
WEBDAV_USER="你的WebDAV用户名"
WEBDAV_PASSWORD="你的WebDAV密码"
```

## 每天定时执行

例如每天 03:30：

```cron
30 3 * * * /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh >> /var/log/obsidian-webdav-backup.log 2>&1
```

注意：当前是覆盖上传，不会删除 WebDAV 上已经存在、但后来从源仓库删除的文件。
