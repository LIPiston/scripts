#!/bin/bash

# 作者 LIPiston
# 作用 启动或进入持久化 Hermes TUI tmux 会话。
# - Windows：在 tmux 中先运行 PowerShell，再由 PowerShell 从用户主目录启动 Hermes TUI。
# - 其他系统：在 tmux 中直接从用户主目录启动 Hermes TUI。
# - 如果 tmux 会话 hermesK 已存在：直接进入该会话。

_hermesK_is_windows() {
    case "${OSTYPE:-}:$(uname -s 2>/dev/null)" in
        cygwin*:MINGW*|cygwin*:MSYS*|msys*:MINGW*|msys*:MSYS*|*:MINGW*|*:MSYS*|*:CYGWIN*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_hermesK_create_session() {
    local session="$1"
    local start_dir="$2"

    if _hermesK_is_windows; then
        local windows_start_dir

        if ! command -v powershell.exe >/dev/null 2>&1; then
            printf 'hermesK: powershell.exe not found in PATH\n' >&2
            return 127
        fi

        # 先把 /c/Users/... 转成真正的 C:\Users\...，避免 MSYS/Git Bash
        # 把盘符路径错误传给 Hermes，产生 C:\c、D:\d 一类垃圾目录。
        if command -v cygpath >/dev/null 2>&1; then
            windows_start_dir="$(cygpath -w "$start_dir")" || return
        else
            windows_start_dir="$start_dir"
        fi

        # tmux 先进入真实 Windows 主目录，再启动 PowerShell，并由 PowerShell 运行 Hermes TUI。
        tmux new-session -d -s "$session" -c "$windows_start_dir" \
            powershell.exe -NoLogo -NoProfile -NoExit -Command 'hermes --tui'
    else
        if ! command -v hermes >/dev/null 2>&1; then
            printf 'hermesK: hermes not found in PATH\n' >&2
            return 127
        fi

        tmux new-session -d -s "$session" -c "$start_dir" hermes --tui
    fi
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
