# obsidian-webdav-backup

每天把 starxn 上 Gitea 的 `vault-git` 工作区文件覆盖备份到 WebDAV；不上传 `.git`，因此不备份 Git 历史、对象和索引。

## 配置方式

不使用 `.env`。直接编辑 `backup_obsidian_webdav.sh` 开头的“用户配置区”：

```bash
VAULT_GIT_DIR="/root/data/vault-git"
GIT_REMOTE="https://gitea.example.com/用户名/vault-git.git"
GIT_USERNAME="你的Gitea用户名"
GIT_PASSWORD="你的Gitea密码或Access Token"
GIT_PULL="true"
WEBDAV_URL="https://你的-webdav地址"
WEBDAV_REMOTE_DIR="obsidian-vault"
WEBDAV_USER="你的WebDAV用户名"
WEBDAV_PASSWORD="你的WebDAV密码"
```

脚本内置占位符检查，未修改时会直接退出。密码和 Token 不要提交到 GitHub；上传 GitHub 的版本应保留占位符。

## 执行流程

1. 检查占位符和依赖；
2. 使用 Gitea HTTPS URL、用户名和密码执行 `git ls-remote` 验证；
3. 默认执行 `git pull --ff-only` 获取最新内容；
4. 拉取失败或认证失败时停止，不上传旧内容；
5. 排除 `.git`，上传工作区文件到 WebDAV，同名文件覆盖；
6. 自动创建 WebDAV 目录，并用锁目录防止重复执行。

`GIT_PASSWORD` 推荐填写 Gitea Access Token，而不是账户登录密码。

## 安装到 starxn

```bash
mkdir -p /root/bin/obsidian-webdav-backup
curl -fL https://raw.githubusercontent.com/LIPiston/scripts/main/obsidian-webdav-backup/backup_obsidian_webdav.sh \
  -o /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh
chmod 700 /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh
vi /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh
```

填写配置后手动测试：

```bash
/root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh
```

## 每天定时执行

例如每天 03:30：

```cron
30 3 * * * /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh >> /var/log/obsidian-webdav-backup.log 2>&1
```

注意：当前是覆盖上传，不会删除 WebDAV 上已经存在、但后来从源仓库删除的文件。
