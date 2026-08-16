#!/usr/bin/env bash
# Obsidian vault-git -> WebDAV 覆盖备份
# 使用前只需修改下面“用户配置区”的占位符。

set -Eeuo pipefail
IFS=$'\n\t'

# ========================= 用户配置区 =========================
VAULT_GIT_DIR="/root/path/to/vault-git"

# Git 仓库 HTTPS Clone URL；也支持 SSH URL，但 SSH 不使用用户名/密码。
GIT_REMOTE="https://gitea.example.com/USERNAME/vault-git.git"
GIT_USERNAME="YOUR_GIT_USERNAME"
GIT_PASSWORD="YOUR_GIT_PASSWORD_OR_ACCESS_TOKEN"
GIT_PULL="true"

WEBDAV_URL="https://webdav.example.com/dav"
WEBDAV_REMOTE_DIR="obsidian-vault"
WEBDAV_USER="YOUR_WEBDAV_USERNAME"
WEBDAV_PASSWORD="YOUR_WEBDAV_PASSWORD"
# =============================================================

LOG_PREFIX='[obsidian-webdav-backup]'
CURL_BIN="curl"
GIT_BIN="git"

log() { printf '%s %s\n' "$LOG_PREFIX" "$*"; }
die() { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

for value_name in VAULT_GIT_DIR GIT_REMOTE GIT_USERNAME GIT_PASSWORD WEBDAV_URL WEBDAV_USER WEBDAV_PASSWORD; do
  value="${!value_name}"
  [[ -n "$value" && "$value" != *YOUR_* && "$value" != *CHANGE_ME* && "$value" != */path/to/* ]] || \
    die "请先修改脚本开头的占位符：$value_name"
done

[[ -d "$VAULT_GIT_DIR" ]] || die "源目录不存在：$VAULT_GIT_DIR"
[[ -d "$VAULT_GIT_DIR/.git" ]] || die "源目录不是 Git 仓库：$VAULT_GIT_DIR"
command -v "$CURL_BIN" >/dev/null 2>&1 || die "找不到 curl"
command -v "$GIT_BIN" >/dev/null 2>&1 || die "找不到 git"

LOCK_DIR="${TMPDIR:-/tmp}/obsidian-webdav-backup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  die "已有另一个备份进程运行中（锁目录：$LOCK_DIR）"
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# 仅 HTTPS Git URL 使用用户名/密码；不要把 HTTPS URL 交给 ssh。
case "$GIT_REMOTE" in
  https://*|http://*)
    git_auth_url="${GIT_REMOTE/\/\//@${GIT_USERNAME}:$GIT_PASSWORD@}"
    git_ls_remote=("$GIT_BIN" -c credential.helper= ls-remote "$git_auth_url" HEAD)
    git_pull=("$GIT_BIN" -c credential.helper= pull --ff-only "$git_auth_url" HEAD)
    ;;
  git@*|ssh://*)
    log "检测到 SSH Git 地址，使用 SSH 密钥验证（忽略 GIT_USERNAME/GIT_PASSWORD）"
    git_ls_remote=("$GIT_BIN" ls-remote "$GIT_REMOTE" HEAD)
    git_pull=("$GIT_BIN" pull --ff-only "$GIT_REMOTE" HEAD)
    ;;
  *)
    die "不支持的 GIT_REMOTE 格式：请使用 https://、git@ 或 ssh://"
    ;;
esac

log "验证 Git 凭据"
if ! (cd "$VAULT_GIT_DIR" && GIT_TERMINAL_PROMPT=0 "${git_ls_remote[@]}" >/dev/null); then
  die "Git 验证失败，请检查 GIT_REMOTE、GIT_USERNAME 和 GIT_PASSWORD；若使用 SSH 地址，请检查 SSH 密钥"
fi

if [[ "$GIT_PULL" == "true" ]]; then
  log "拉取 Git 最新内容"
  if ! (cd "$VAULT_GIT_DIR" && GIT_TERMINAL_PROMPT=0 "${git_pull[@]}"); then
    die "git pull 失败，已停止备份"
  fi
fi

webdav_request() {
  "$CURL_BIN" --fail --silent --show-error --retry 3 --retry-delay 2 \
    --user "$WEBDAV_USER:$WEBDAV_PASSWORD" "$@"
}

remote_path() {
  local rel="$1"
  printf '%s/%s' "${WEBDAV_URL%/}" "${WEBDAV_REMOTE_DIR#/}/$rel"
}

mkdir_remote_path() {
  local rel_dir="$1" part path=''
  [[ -z "$rel_dir" ]] && return 0
  while IFS= read -r part; do
    [[ -z "$part" ]] && continue
    path="${path:+$path/}$part"
    if ! webdav_request -X MKCOL "$(remote_path "$path")" >/dev/null 2>&1; then
      local code
      code="$("$CURL_BIN" --silent --output /dev/null --write-out '%{http_code}' \
        --user "$WEBDAV_USER:$WEBDAV_PASSWORD" -X MKCOL "$(remote_path "$path")")"
      [[ "$code" == "405" || "$code" == "409" ]] || die "无法创建 WebDAV 目录：$path（HTTP $code）"
    fi
  done < <(printf '%s' "$rel_dir" | tr '/' '\n')
}

mapfile -d '' FILES < <(cd "$VAULT_GIT_DIR" && find . -path './.git' -prune -o -type f -print0)
mapfile -d '' DIRS < <(cd "$VAULT_GIT_DIR" && find . -path './.git' -prune -o -type d -print0)

log "开始覆盖备份：$VAULT_GIT_DIR -> ${WEBDAV_URL%/}/$WEBDAV_REMOTE_DIR"
for dir in "${DIRS[@]}"; do
  rel="${dir#./}"
  [[ "$rel" == "$dir" ]] && continue
  mkdir_remote_path "$WEBDAV_REMOTE_DIR/$rel"
done

for file in "${FILES[@]}"; do
  rel="${file#./}"
  parent="${rel%/*}"
  [[ "$parent" == "$rel" ]] || mkdir_remote_path "$WEBDAV_REMOTE_DIR/$parent"
  log "上传：$rel"
  webdav_request -T "$VAULT_GIT_DIR/$rel" "$(remote_path "$WEBDAV_REMOTE_DIR/$rel")" >/dev/null
done

log "备份完成：${#FILES[@]} 个文件（已排除 .git）"
