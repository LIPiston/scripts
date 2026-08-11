# hermesK

`hermesK` 是一个 Bash 函数，用于启动或进入持久化的 Hermes TUI tmux 会话。

## 作用

运行：

```bash
hermesK
```

行为：

- 自动检测当前是否为 Windows Git Bash/MSYS/Cygwin 环境。
- Windows：先把 Git Bash 的 `/c/Users/...` 转换为真实 Windows 路径，再让 tmux 在该目录启动 `powershell.exe` 并运行 `hermes --tui`。
- Linux/macOS：在 tmux 会话中直接从用户主目录运行 `hermes --tui`。
- 如果 tmux 会话 `hermesK` 已存在：直接进入该会话，不重复启动 Hermes。
- 如果当前已经在 tmux 内：切换到 `hermesK` 会话。
- 如果当前不在 tmux 内：附加到 `hermesK` 会话。

Windows 使用 PowerShell 启动，是为了避免 Git Bash/MSYS 在启动 Hermes TUI 时错误转换 Windows 盘符路径，产生类似 `C:\\c`、`D:\\d` 之类的错误工作目录或垃圾目录。

## 依赖

所有系统均需要：

- `tmux`
- `hermes`

Windows 还需要：

- `powershell.exe`（Windows PowerShell 5.1 即可）

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

检查 Windows 检测结果：

```bash
_hermesK_is_windows && echo Windows || echo POSIX
```
