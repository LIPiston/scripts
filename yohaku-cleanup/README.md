# yohaku-cleanup

清理 Yohaku 部署服务器上的旧版本目录，释放磁盘空间。

## 背景

[yohaku-deploy-action](https://github.com/LIPiston/yohaku-deploy-action) 的 GitHub Actions 工作流每次部署都会在服务器 `~/yohaku/` 下新建一个以 `run_number` 命名的全量快照目录（如 `52/`、`51/`），**没有任何自动清理机制**。每个版本约 300~400M，长期累积可占用数 G 磁盘空间。

目录结构示意：

```
~/yohaku/
├── .env                    # 环境变量（各版本软链共享，勿删）
├── .cache/                 # 共享缓存（勿删）
├── ecosystem.config.js     # PM2 配置（勿删）
├── server.js -> 52/standalone/apps/web/server.js   # 当前版本软链
├── public -> 52/standalone/apps/web/public         # 当前版本软链
├── 52/                     # 当前运行版本
├── 51/                     # 上一个版本（回滚点）
├── 49/ 47/ 46/ ...         # 历史版本（可清理）
└── 4/                      # 最旧版本
```

## 功能

- 保留最近 N 个版本（默认 5），删除更早的历史版本
- **自动保护当前运行版本**：读取 `server.js` / `public` 软链指向的版本，无论如何都不会误删
- 只处理纯数字目录，`.env`、`.cache`、`ecosystem.config.js` 等公共文件不碰
- 删除后自检软链有效性，失效则报错退出
- 支持 `--dry-run` 预览模式

## 部署到服务器

```bash
# 上传脚本（starxn 服务器）
scp cleanup_yohaku.sh starxn:/root/cleanup_yohaku.sh

# 试运行（只预览不删除）
bash /root/cleanup_yohaku.sh --dry-run

# 正式执行（保留最近 5 个版本）
bash /root/cleanup_yohaku.sh
```

## 1Panel 定时任务配置

1. 1Panel → 计划任务 → 创建任务
2. 任务类型：**Shell 脚本**
3. 执行命令：

   ```
   bash /root/cleanup_yohaku.sh
   ```

4. 执行周期：建议**每月**一次（每次部署新增约 380M，月度清理可稳定控制磁盘占用）
5. 创建后先点「执行」手动跑一次验证输出

## 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `KEEP`（位置参数） | 保留最近几个版本 | `5` |
| `--dry-run` | 只预览删除列表与预计释放空间，不执行 | - |
| 环境变量 `YOHAKU_DIR` | yohaku 目录路径 | `/root/yohaku` |

示例：

```bash
bash cleanup_yohaku.sh 3          # 只保留最近 3 个版本
bash cleanup_yohaku.sh --dry-run  # 预览
YOHAKU_DIR=/home/u/yohaku bash cleanup_yohaku.sh  # 自定义目录
```

## 安全设计

1. **软链保护**：运行时先解析 `server.js` / `public` 指向的版本号，加入保留列表。即使手动 rollback 过（`rollback.sh` 切换了软链），当前生效版本也永远不会被删。
2. **严格匹配**：只用正则 `^[0-9]+$` 匹配数字目录，`.env` 等隐藏文件、`public`/`server.js` 软链本身均不匹配。
3. **失败即停**：任一目录删除失败立即退出，避免半途而废留下不一致状态。
4. **删除后自检**：校验 `server.js` / `public` 软链仍有效，失效时报错（防止站点因误删而挂掉）。

## 实测记录（2026-08-15，starxn 服务器）

- 清理前：26 个版本目录共 **8.6G**，磁盘占用 89%
- 保留 `52`（当前）`51` `49` `47` `46`，删除 21 个旧版本
- 释放 **6.3G**，磁盘占用降至 66%
- 清理后 pm2 进程 online、站点 HTTP 200，无影响
