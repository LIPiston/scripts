#!/usr/bin/env bash
#
# starxn DERP 证书同步脚本
#
# 将 1Panel 当前证书复制到 DERP Compose 的 data 目录，并重启 DERP 容器。
# 脚本不使用符号链接，兼容 Docker 对 data 目录的独立挂载。
#
# 用法：
#   bash sync_derper_cert.sh --dry-run
#   bash sync_derper_cert.sh
#
# 适合配置为 1Panel 每周 Shell 计划任务运行。
#
# 安全特性：
#   - 只操作配置的两个证书目标文件；
#   - 仅在证书或私钥发生变化时备份旧文件；
#   - 采用临时文件 + 原子替换，避免写入半个证书；
#   - 每次正式同步都会重启 DERP；
#   - 不自动删除历史备份；
#   - 使用锁避免多个计划任务并发执行；
#   - 支持 --dry-run。

set -Eeuo pipefail

# ======================== 配置区 ========================
# 用户可按实际部署修改以下路径。
DERP_COMPOSE_DIR="${DERP_COMPOSE_DIR:-/opt/1panel/docker/compose/tailscale-derper}"
DERP_SERVICE="${DERP_SERVICE:-derper}"
DERP_CONTAINER="${DERP_CONTAINER:-tailscale-derper}"

# 1Panel 当前站点证书来源。
SOURCE_CERT="${SOURCE_CERT:-/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/fullchain.pem}"
SOURCE_KEY="${SOURCE_KEY:-/opt/1panel/www/sites/derper.lipiston.eu.org/ssl/privkey.pem}"

# DERP data 目录及目标文件。
DERP_DATA_DIR="${DERP_DATA_DIR:-$DERP_COMPOSE_DIR/data}"
TARGET_CERT="${TARGET_CERT:-$DERP_DATA_DIR/derper.lipiston.eu.org.crt}"
TARGET_KEY="${TARGET_KEY:-$DERP_DATA_DIR/derper.lipiston.eu.org.key}"

# 备份目录不会自动清理；只有内容发生变化时才创建备份。
BACKUP_DIR="${BACKUP_DIR:-$DERP_DATA_DIR/cert-sync-backups}"
LOCK_FILE="${LOCK_FILE:-/run/lock/starxn-derper-cert-sync.lock}"
DERP_DOMAIN="${DERP_DOMAIN:-derper.lipiston.eu.org}"
HEALTH_URL="${HEALTH_URL:-https://$DERP_DOMAIN/generate_204}"
# ========================================================

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
elif [[ $# -gt 0 ]]; then
  echo "ERROR: 未知参数: $1" >&2
  echo "用法: $0 [--dry-run]" >&2
  exit 2
fi

log() {
  printf '[%s] %s\n' "$(date '+%F %T%z')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

cleanup_tmp() {
  [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && rm -rf -- "$TMP_DIR"
}
trap cleanup_tmp EXIT

# 仅使用 mkdir 原子抢锁，避免依赖 flock 包；退出时释放锁。
acquire_lock() {
  local lock_parent
  lock_parent=$(dirname "$LOCK_FILE")
  mkdir -p "$lock_parent"
  if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    fail "已有另一个同步任务运行，锁目录: $LOCK_FILE"
  fi
  trap 'rmdir -- "$LOCK_FILE" 2>/dev/null || true; cleanup_tmp' EXIT
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "文件不存在: $path"
  [[ -r "$path" ]] || fail "文件不可读: $path"
}

sha256() {
  sha256sum "$1" | awk '{print $1}'
}

cert_summary() {
  openssl x509 -in "$1" -noout -subject -issuer -dates -ext subjectAltName
}

validate_source_cert() {
  log "检查来源证书: $SOURCE_CERT"
  cert_summary "$SOURCE_CERT" || fail "来源证书不是有效 PEM X.509 证书"
  if ! openssl x509 -in "$SOURCE_CERT" -noout -ext subjectAltName \
      | grep -Eq "DNS:\*\.${DERP_DOMAIN#*.}|DNS:${DERP_DOMAIN}"; then
    fail "来源证书 SAN 未发现 $DERP_DOMAIN 或对应泛域名"
  fi
}

same_content() {
  local src="$1" dst="$2"
  [[ -f "$dst" ]] && cmp -s "$src" "$dst"
}

show_plan() {
  log "来源证书: $SOURCE_CERT"
  log "来源私钥: $SOURCE_KEY"
  log "目标证书: $TARGET_CERT"
  log "目标私钥: $TARGET_KEY"
  log "备份目录: $BACKUP_DIR"
  log "证书内容变化: $CERT_CHANGED"
  log "私钥内容变化: $KEY_CHANGED"
}

acquire_lock

[[ "$(id -u)" -eq 0 ]] || fail "必须以 root 运行"
command -v openssl >/dev/null 2>&1 || fail "缺少 openssl"
command -v sha256sum >/dev/null 2>&1 || fail "缺少 sha256sum"
command -v docker >/dev/null 2>&1 || fail "缺少 docker"

[[ -d "$DERP_COMPOSE_DIR" ]] || fail "Compose 目录不存在: $DERP_COMPOSE_DIR"
[[ -d "$DERP_DATA_DIR" ]] || fail "DERP data 目录不存在: $DERP_DATA_DIR"
require_file "$SOURCE_CERT"
require_file "$SOURCE_KEY"
validate_source_cert

CERT_CHANGED=0
KEY_CHANGED=0
if ! same_content "$SOURCE_CERT" "$TARGET_CERT"; then CERT_CHANGED=1; fi
if ! same_content "$SOURCE_KEY" "$TARGET_KEY"; then KEY_CHANGED=1; fi

show_plan

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN：将创建备份并同步证书，每次正式运行都会重启容器；本次不会写入或重启。"
  exit 0
fi

TMP_DIR=$(mktemp -d "$DERP_DATA_DIR/.cert-sync.XXXXXX")

# 先生成临时副本并验证，避免把损坏文件写入运行目录。
install -m 644 "$SOURCE_CERT" "$TMP_DIR/derper.lipiston.eu.org.crt"
install -m 600 "$SOURCE_KEY" "$TMP_DIR/derper.lipiston.eu.org.key"
openssl x509 -in "$TMP_DIR/derper.lipiston.eu.org.crt" -noout >/dev/null

backup_one() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  cp -a -- "$target" "$BACKUP/"
}

if [[ "$CERT_CHANGED" -eq 1 || "$KEY_CHANGED" -eq 1 ]]; then
  BACKUP="$BACKUP_DIR/$(date '+%Y%m%d-%H%M%S')"
  mkdir -p -m 700 "$BACKUP"
  backup_one "$TARGET_CERT"
  backup_one "$TARGET_KEY"
  log "备份已创建: $BACKUP"
else
  BACKUP=""
  log "证书和私钥内容均未变化，不创建备份；仍将同步并重启 DERP。"
fi

mv -f -- "$TMP_DIR/derper.lipiston.eu.org.crt" "$TARGET_CERT"
mv -f -- "$TMP_DIR/derper.lipiston.eu.org.key" "$TARGET_KEY"

# 写入后读取回验证内容和格式。
[[ "$(sha256 "$SOURCE_CERT")" == "$(sha256 "$TARGET_CERT")" ]] \
  || fail "目标证书校验和与来源不一致"
[[ "$(sha256 "$SOURCE_KEY")" == "$(sha256 "$TARGET_KEY")" ]] \
  || fail "目标私钥校验和与来源不一致"
openssl x509 -in "$TARGET_CERT" -noout >/dev/null \
  || fail "目标证书写入后无法解析"

log "目标文件已更新，开始重启 DERP 容器。"
cd "$DERP_COMPOSE_DIR"
docker compose restart "$DERP_SERVICE"

# 等待容器恢复并检查实际状态。
for _ in {1..15}; do
  state=$(docker inspect "$DERP_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || true)
  [[ "$state" == "running" ]] && break
  sleep 1
done
state=$(docker inspect "$DERP_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || true)
[[ "$state" == "running" ]] || fail "DERP 容器未恢复，当前状态: ${state:-unknown}"

# 通过容器内路径确认 DERP 实际看到的证书，而不是只看宿主机文件。
docker exec "$DERP_CONTAINER" test -r "/app/certs/derper.lipiston.eu.org.crt" \
  || fail "容器内证书不可读"
docker exec "$DERP_CONTAINER" test -r "/app/certs/derper.lipiston.eu.org.key" \
  || fail "容器内私钥不可读"
docker exec "$DERP_CONTAINER" openssl x509 \
  -in "/app/certs/derper.lipiston.eu.org.crt" -noout >/dev/null \
  || fail "容器内证书无法解析"

if command -v curl >/dev/null 2>&1; then
  code=$(curl -4 -skS -o /dev/null -w '%{http_code}' --max-time 15 "$HEALTH_URL" || true)
  [[ "$code" == "204" ]] || fail "DERP 健康检查失败，HTTP 状态: ${code:-empty}"
  log "健康检查通过: $HEALTH_URL -> $code"
else
  log "WARNING: 本机缺少 curl，跳过公网健康检查。"
fi

log "同步完成。证书来源和目标 SHA-256："
log "cert $(sha256 "$SOURCE_CERT")"
log "key  $(sha256 "$SOURCE_KEY")"
if [[ -n "$BACKUP" ]]; then
  log "备份保留在: $BACKUP"
fi
