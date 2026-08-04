#!/bin/bash

# 作者 LIPiston
# 作用 启动或进入持久化 Hermes tmux 会话。
# - 如果 tmux 会话 hermesK 不存在：在 ~ 目录运行 hermes 创建会话。
# - 如果 tmux 会话 hermesK 已存在：直接进入该会话。
# - 如果当前已经在 tmux 内：切换到 hermesK 会话。

hermesK() {
    local session="hermesK"
    local start_dir="$HOME"

    if ! command -v tmux >/dev/null 2>&1; then
        printf 'hermesK: tmux not found in PATH\n' >&2
        return 127
    fi

    if [ -n "${TMUX:-}" ]; then
        tmux has-session -t "$session" 2>/dev/null || \
            tmux new-session -d -s "$session" -c "$start_dir" hermes
        tmux switch-client -t "$session"
    else
        tmux new-session -A -s "$session" -c "$start_dir" hermes
    fi
}
