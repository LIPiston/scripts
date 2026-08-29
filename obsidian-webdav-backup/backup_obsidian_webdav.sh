#!/usr/bin/env bash
# Obsidian vault-git -> WebDAV 覆盖备份
# 使用前只需修改下面“用户配置区”的占位符。
# GitHub 公開版：仅保留占位符，不包含真实凭据。

set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C

# ========================= 用户配置区 =========================
VAULT_GIT_DIR="/opt/obsidian"

# Git 仓库 HTTPS Clone URL；HTTPS 使用用户名密码，SSH 使用 SSH 密钥。
GIT_REMOTE="https://git.example.com/USERNAME/vault.git"
GIT_USERNAME="YOUR_GIT_USERNAME"
GIT_PASSWORD="YOUR_GIT_PASSWORD_OR_ACCESS_TOKEN"

WEBDAV_URL="https://files.example.com/dav"
WEBDAV_REMOTE_DIR="obsidian-vault"
WEBDAV_USER="YOUR_WEBDAV_USERNAME"
WEBDAV_PASSWORD="YOUR_WEBDAV_PASSWORD"
# =============================================================

LOG_PREFIX='[obsidian-webdav-backup]'
CURL_BIN="curl"
GIT_BIN="git"
ZIP_BIN="zip"
PYTHON_BIN="python3"
ZIP_FILE_NAME="obsidian-vault-$(date +%F).zip"
# WebDAV 中保留的 ZIP 备份份数；例如 7 表示保留最新 7 份。
WEBDAV_KEEP_COUNT="7"

log() { printf '%s %s\n' "$LOG_PREFIX" "$*"; }
die() { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

for value_name in VAULT_GIT_DIR GIT_REMOTE GIT_USERNAME GIT_PASSWORD WEBDAV_URL WEBDAV_USER WEBDAV_PASSWORD; do
  value="${!value_name}"
  [[ -n "$value" && "$value" != *YOUR_* && "$value" != *CHANGE_ME* && "$value" != */path/to/* ]] || \
    die "请先修改脚本开头的占位符：$value_name"
done

[[ "$WEBDAV_KEEP_COUNT" =~ ^[1-9][0-9]*$ ]] || \
  die "WEBDAV_KEEP_COUNT 必须是大于等于 1 的整数"

command -v "$CURL_BIN" >/dev/null 2>&1 || die "找不到 curl"
command -v "$GIT_BIN" >/dev/null 2>&1 || die "找不到 git"
command -v "$ZIP_BIN" >/dev/null 2>&1 || die "找不到 zip，请先安装 zip"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "找不到 python3，请先安装 Python 3"

LOCK_DIR="${TMPDIR:-/tmp}/obsidian-webdav-backup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  die "已有另一个备份进程运行中（锁目录：$LOCK_DIR）"
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# HTTPS Git 使用临时 askpass，不把密码放进 remote URL、进程参数或 Git 配置。
askpass_file="$(mktemp)"
chmod 700 "$askpass_file"
cat > "$askpass_file" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "$GIT_USERNAME" ;;
  *Password*) printf '%s\n' "$GIT_PASSWORD" ;;
  *) printf '\n' ;;
esac
ASKPASS
trap 'rm -f "$askpass_file"; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

case "$GIT_REMOTE" in
  https://*|http://*)
    git_ls_remote=("$GIT_BIN" -c credential.helper= ls-remote "$GIT_REMOTE" HEAD)
    git_clone=("$GIT_BIN" -c credential.helper= clone "$GIT_REMOTE" "$VAULT_GIT_DIR")
    ;;
  git@*|ssh://*)
    log "检测到 SSH Git 地址，使用 SSH 密钥验证"
    git_ls_remote=("$GIT_BIN" ls-remote "$GIT_REMOTE" HEAD)
    git_clone=("$GIT_BIN" clone "$GIT_REMOTE" "$VAULT_GIT_DIR")
    ;;
  *)
    die "不支持的 GIT_REMOTE 格式：请使用 https://、git@ 或 ssh://"
    ;;
esac

log "验证 Git 凭据"
if ! (GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$askpass_file" \
  GIT_USERNAME="$GIT_USERNAME" GIT_PASSWORD="$GIT_PASSWORD" \
  "${git_ls_remote[@]}" >/dev/null); then
  die "Git 验证失败，请检查 GIT_REMOTE、GIT_USERNAME 和 GIT_PASSWORD；若使用 SSH 地址，请检查 SSH 密钥"
fi

# 每次都删除本地工作树后重新 clone，确保内容完全跟随远端 HEAD，
# 不受本地改动、未跟踪文件或旧 Git 状态影响。
log "删除旧的本地 Git 工作树：$VAULT_GIT_DIR"
rm -rf -- "$VAULT_GIT_DIR"

log "重新 Clone Git 最新内容"
if ! (GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$askpass_file" \
  GIT_USERNAME="$GIT_USERNAME" GIT_PASSWORD="$GIT_PASSWORD" \
  "${git_clone[@]}"); then
  die "git clone 失败，已停止备份"
fi

[[ -d "$VAULT_GIT_DIR/.git" ]] || die "git clone 完成后未找到 Git 仓库：$VAULT_GIT_DIR"

TMP_ZIP="$(mktemp --tmpdir --suffix=.zip obsidian-vault.XXXXXX)"
# mktemp 会先创建空文件；zip 需要目标不存在，否则会把它当作损坏的旧压缩包。
rm -f -- "$TMP_ZIP"
cleanup_zip() { rm -f -- "$TMP_ZIP"; }
trap 'cleanup_zip; rm -f "$askpass_file"; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

log "打包 Git 工作树为 ZIP"
if ! (cd "$VAULT_GIT_DIR" && "$ZIP_BIN" -q -r -X "$TMP_ZIP" . -x '.git/*'); then
  die "ZIP 打包失败，已停止备份"
fi

zip_size="$(stat -c '%s' "$TMP_ZIP")"
log "ZIP 打包完成：${zip_size} bytes"

webdav_request() {
  "$CURL_BIN" --fail --silent --show-error --retry 3 --retry-delay 2 \
    --user "$WEBDAV_USER:$WEBDAV_PASSWORD" "$@"
}

remote_path() {
  local rel="$1" segment encoded_path='' first=1
  while IFS= read -r segment; do
    [[ -z "$segment" ]] && continue
    encoded=''
    LC_ALL=C
    for ((i=0; i<${#segment}; i++)); do
      char="${segment:i:1}"
      case "$char" in
        [a-zA-Z0-9._~-]) encoded+="$char" ;;
        *) printf -v escaped '%%%02X' "'${char}"; encoded+="$escaped" ;;
      esac
    done
    if (( first )); then
      encoded_path="$encoded"
      first=0
    else
      encoded_path="$encoded_path/$encoded"
    fi
  done < <(printf '%s' "$rel" | tr '/' '\n')
  printf '%s/%s' "${WEBDAV_URL%/}" "${WEBDAV_REMOTE_DIR#/}/$encoded_path"
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

cleanup_old_backups() {
  local backup_url name
  local -a backups=()
  mapfile -t backups < <(
    webdav_request -X PROPFIND -H 'Depth: 1' -H 'Content-Type: application/xml' \
      "$(remote_path '')" 2>/dev/null |
      "$PYTHON_BIN" -c 'import re,sys,urllib.parse
text=sys.stdin.read()
for href in re.findall(r"<(?:[A-Za-z0-9_-]+:)?href[^>]*>(.*?)</(?:[A-Za-z0-9_-]+:)?href>", text, re.I|re.S):
    url=urllib.parse.unquote(href).strip()
    name=url.rstrip("/").rsplit("/",1)[-1]
    if re.fullmatch(r"obsidian-vault-[0-9]{4}-[0-9]{2}-[0-9]{2}\\.zip", name):
        print(url)'
  )

  ((${#backups[@]} > WEBDAV_KEEP_COUNT)) || return 0
  mapfile -t backups < <(printf '%s\n' "${backups[@]}" | sort -r)
  for ((i=WEBDAV_KEEP_COUNT; i<${#backups[@]}; i++)); do
    backup_url="${backups[i]}"
    name="${backup_url##*/}"
    log "删除过期备份：$name"
    webdav_request -X DELETE "$backup_url" >/dev/null
  done
}

log "上传 ZIP：$ZIP_FILE_NAME"
webdav_request --progress-bar -T "$TMP_ZIP" "$(remote_path "$ZIP_FILE_NAME")"
printf '\n'

cleanup_old_backups
log "备份完成：ZIP ${zip_size} bytes，保留最近 ${WEBDAV_KEEP_COUNT} 份（已排除 .git）"
