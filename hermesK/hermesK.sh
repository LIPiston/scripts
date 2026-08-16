#!/bin/bash

# 作者 LIPiston
# 作用 启动或进入持久化 Hermes TUI tmux 会话。
# - 所有系统：tmux 从用户主目录直接启动 Hermes TUI（Windows 下 hermes 在 PATH 中，
#   无需 PowerShell 中转）。
# - 如果 tmux 会话 hermesK 已存在：直接进入该会话。

_hermesK_create_session() {
    local session="$1"
    local start_dir="$2"

    if ! command -v hermes >/dev/null 2>&1; then
        printf 'hermesK: hermes not found in PATH\n' >&2
        return 127
    fi

    # 整条命令必须包成单个参数传给 tmux：Windows 下的原生 tmux（WinGet 包
    # marlocarlo.psmux）只把第一个参数当命令，分开传参 --tui 会被丢弃。
    # -c 传 POSIX 路径（/c/Users/...），MSYS 会自动转换为 Windows 路径，
    # 避免直接传 C:\... 而产生 C:\c 一类垃圾目录。
    tmux new-session -d -s "$session" -c "$start_dir" "hermes --tui"
}

hermesK() {
    local session="hermesK"
    local start_dir="$HOME"

    if ! command -v tmux >/dev/null 2>&1; then
        printf 'hermesK: tmux not found in PATH\n' >&2
        return 127
    fi

    if ! tmux has-session -t "$session" 2>/dev/null; then
        _hermesK_create_session "$session" "$start_dir" || return
    fi

    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "$session"
    else
        tmux attach-session -t "$session"
    fi
}
