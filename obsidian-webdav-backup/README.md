# obsidian-webdav-backup

每天从 starxn 上的 Git 仓库重新 clone 工作树，打包为带日期的 ZIP，然后上传到 WebDAV；不上传 `.git`，并按 `WEBDAV_KEEP_COUNT` 清理旧备份。

## 配置方式

直接编辑 `backup_obsidian_webdav.sh` 顶部的“用户配置区”：

```bash
VAULT_GIT_DIR="/root/data/vault-git"
GIT_REMOTE="https://git.example.com/用户名/vault-git.git"
GIT_USERNAME="你的Git用户名"
GIT_PASSWORD="你的Git密码或Access Token"
WEBDAV_URL="https://你的-webdav地址"
WEBDAV_REMOTE_DIR="obsidian-vault"
WEBDAV_USER="你的WebDAV用户名"
WEBDAV_PASSWORD="你的WebDAV密码"
WEBDAV_KEEP_COUNT="7"
```

`WEBDAV_KEEP_COUNT` 表示保留最新多少份日期 ZIP，例如 `7` 表示保留最近 7 份。
脚本只会清理 `obsidian-vault-YYYY-MM-DD.zip` 格式的备份，不会删除其他 WebDAV 文件。

Git 地址支持 `https://`、`http://`、`git@` 和 `ssh://`。HTTPS 使用临时 askpass，SSH 使用 SSH 密钥。

## 执行流程

1. 检查配置、依赖和保留份数；
2. 验证 Git 仓库凭据；
3. 删除旧的本地工作树并重新执行 `git clone`；
4. 使用 `zip` 打包工作树并排除 `.git`；
5. 上传为 `obsidian-vault-YYYY-MM-DD.zip`，显示上传进度；
6. 列出 WebDAV 中的日期备份并删除超出保留数量的旧备份。

## 安装到 starxn

```bash
mkdir -p /root/bin/obsidian-webdav-backup
curl -fL https://raw.githubusercontent.com/LIPiston/scripts/main/obsidian-webdav-backup/backup_obsidian_webdav.sh \
  -o /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh
chmod 700 /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh
vi /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh
```

依赖：`bash`、`curl`、`git`、`zip` 和 `python3`。

填写配置后手动测试：

```bash
/root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh
```

## 每天定时执行

例如每天 03:30：

```cron
30 3 * * * /root/bin/obsidian-webdav-backup/backup_obsidian_webdav.sh >> /var/log/obsidian-webdav-backup.log 2>&1
```

脚本只清理符合日期命名规则的 ZIP 文件；其他 WebDAV 文件不会被删除。
