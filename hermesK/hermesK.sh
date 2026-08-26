#!/bin/bash

# 作者 LIPiston
# 作用 启动或进入持久化 Hermes tmux 会话。
# - Windows：在 tmux 中先运行 pwsh（PowerShell 7.x），再由 pwsh 从用户主目录启动普通模式 Hermes。
# - Linux 等其他系统：在 tmux 中直接从用户主目录启动普通模式 Hermes。
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

    # 整条命令必须包成单个参数传给 tmux：Windows 下的原生 tmux（WinGet 包
    # marlocarlo.psmux）只把第一个参数当命令。
    # -c 传 POSIX 路径（/c/Users/...），MSYS 会自动转换为 Windows 路径，
    # 避免直接传 C:\... 而产生 C:\c 一类垃圾目录。
    if ! command -v hermes >/dev/null 2>&1; then
        printf 'hermesK: hermes not found in PATH\n' >&2
        return 127
    fi

    if _hermesK_is_windows; then
        if ! command -v pwsh.exe >/dev/null 2>&1; then
            printf 'hermesK: pwsh.exe not found in PATH\n' >&2
            return 127
        fi

        # 不把 Git Bash 的 $HOME 传给 Windows 原生 tmux 的 -c：某些 psmux/MSYS
        # 组合会把 /c 错误解释成相对路径，从而产生 C:\\c。让 pwsh 自己
        # 使用 Windows 的用户主目录，并在 PowerShell 中切换目录。
        tmux new-session -d -s "$session" \
            "pwsh.exe -NoLogo -NoProfile -Command \"Set-Location -LiteralPath ([Environment]::GetFolderPath('UserProfile')); hermes\""
    else
        tmux new-session -d -s "$session" -c "$start_dir" "hermes"
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
