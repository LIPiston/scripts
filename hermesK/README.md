# hermesK

`hermesK` 是一个 Bash 函数，用于启动或进入持久化的 Hermes TUI tmux 会话。

## 作用

运行：

```bash
hermesK
```

行为：

- 所有系统一致：在 tmux 会话 `hermesK` 中从用户主目录直接运行 `hermes --tui`。
- Windows 使用原生 tmux（WinGet 包 `marlocarlo.psmux`）时，命令必须整体作为单个参数传给 tmux，因为 psmux 只把第一个参数当命令；`-c` 传 POSIX 路径 `/c/Users/...` 即可，MSYS 会自动转换为 Windows 路径，无需 PowerShell 或 cygpath 中转。
- 如果 tmux 会话 `hermesK` 已存在：直接进入该会话，不重复启动 Hermes。
- 如果当前已经在 tmux 内：切换到 `hermesK` 会话。
- 如果当前不在 tmux 内：附加到 `hermesK` 会话。
- Hermes 退出后窗口与会话随之关闭，下次运行自动重建。

## 依赖

所有系统均需要：

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

检查脚本是否使用 TUI：

```bash
grep -F -- '--tui' /d/LIPis/Documents/code/scripts/hermesK/hermesK.sh
```

## 迁移

旧版本创建的 `hermesK` 会话可能没有启用 TUI（例如早期版本直接运行 `hermes`）。`hermesK` 不会重建已存在的会话，升级后请先删除旧会话，让下一次运行使用新命令：

```bash
tmux kill-session -t hermesK
```
