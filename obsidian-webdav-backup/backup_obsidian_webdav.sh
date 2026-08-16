#!/usr/bin/env bash
# Backup a local vault-git working tree to WebDAV, excluding Git metadata.
# Configuration is read from the adjacent .env file.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
LOG_PREFIX='[obsidian-webdav-backup]'

log() { printf '%s %s\n' "$LOG_PREFIX" "$*"; }
die() { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

[[ -r "$ENV_FILE" ]] || die "配置文件不存在或不可读：$ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${VAULT_GIT_DIR:?请在 .env 设置 VAULT_GIT_DIR}"
: "${WEBDAV_URL:?请在 .env 设置 WEBDAV_URL}"
: "${WEBDAV_USER:?请在 .env 设置 WEBDAV_USER}"
: "${WEBDAV_PASSWORD:?请在 .env 设置 WEBDAV_PASSWORD}"
WEBDAV_REMOTE_DIR="${WEBDAV_REMOTE_DIR:-obsidian-vault}"
CURL_BIN="${CURL_BIN:-curl}"

[[ -d "$VAULT_GIT_DIR" ]] || die "源目录不存在：$VAULT_GIT_DIR"
[[ -d "$VAULT_GIT_DIR/.git" ]] || die "源目录不是 Git 仓库：$VAULT_GIT_DIR"
command -v "$CURL_BIN" >/dev/null 2>&1 || die "找不到 curl：$CURL_BIN"

# Prevent overlapping daily runs.
LOCK_DIR="${TMPDIR:-/tmp}/obsidian-webdav-backup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  die "已有另一个备份进程运行中（锁目录：$LOCK_DIR）"
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# Upload one file, creating its parent collection first.
webdav_request() {
  "$CURL_BIN" --fail --silent --show-error --retry 3 --retry-delay 2 \
    --user "$WEBDAV_USER:$WEBDAV_PASSWORD" "$@"
}

remote_path() {
  local rel="$1"
  printf '%s/%s' "${WEBDAV_URL%/}" "${WEBDAV_REMOTE_DIR#/}/"${rel}
}

mkdir_remote_path() {
  local rel_dir="$1" part path=''
  [[ -z "$rel_dir" ]] && return 0
  while IFS= read -r part; do
    [[ -z "$part" ]] && continue
    path="${path:+$path/}$part"
    # MKCOL 405 means the collection already exists; accept it.
    if ! webdav_request -X MKCOL "$(remote_path "$path")" >/dev/null 2>&1; then
      local code
      code="$("$CURL_BIN" --silent --output /dev/null --write-out '%{http_code}' \
        --user "$WEBDAV_USER:$WEBDAV_PASSWORD" -X MKCOL "$(remote_path "$path")")"
      [[ "$code" == 405 || "$code" == 409 ]] || die "无法创建 WebDAV 目录：$path（HTTP $code）"
    fi
  done < <(printf '%s' "$rel_dir" | tr '/' '\n')
}

# Collect regular files and directories without copying .git or temporary files.
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
