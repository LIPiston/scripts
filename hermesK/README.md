# hermesK

`hermesK` 是一个 Bash 函数，用于启动或进入持久化 Hermes tmux 会话。

## 作用

运行：

```bash
hermesK
```

行为：

- 如果 tmux 会话 `hermesK` 不存在：在 `~` 目录启动 `hermes` 并创建会话。
- 如果 tmux 会话 `hermesK` 已存在：直接进入该会话。
- 如果当前已经在 tmux 内：切换到 `hermesK` 会话。
- 如果当前不在 tmux 内：attach/create `hermesK` 会话。

## 依赖

需要命令可用：

- `tmux`
- `hermes`

## 文件

脚本位置：

```text
D:\LIPis\Documents\code\scripts\hermesK\hermesK.sh
```

Git Bash / MSYS 路径：

```bash
/d/LIPis/Documents/code/scripts/hermesK/hermesK.sh
```

## Bash 配置

把下面内容写入 `~/.bashrc`：

```bash
# User script library commands
if [ -f "/d/LIPis/Documents/code/scripts/hermesK/hermesK.sh" ]; then
  source "/d/LIPis/Documents/code/scripts/hermesK/hermesK.sh"
fi
```

如果使用 `~/.bash_profile` 加载 `~/.bashrc`，确保 `~/.bash_profile` 包含：

```bash
# Load interactive Bash config
[ -f ~/.bashrc ] && source ~/.bashrc
```

配置完成后，新开一个 Git Bash / Tabby 终端，执行：

```bash
hermesK
```

## 手动临时加载

如果不想修改 `~/.bashrc`，也可以在当前 shell 临时加载：

```bash
source /d/LIPis/Documents/code/scripts/hermesK/hermesK.sh
hermesK
```

## 验证

检查脚本语法：

```bash
bash -n /d/LIPis/Documents/code/scripts/hermesK/hermesK.sh
```

检查函数是否已加载：

```bash
type hermesK
```
