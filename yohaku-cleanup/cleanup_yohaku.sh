#!/bin/bash
# ============================================================
# yohaku 旧版本清理脚本
# 保留最近 N 个版本目录（按 run_number 数字从大到小），删除更早的
# 安全保护：当前 server.js / public 软链指向的版本永远保留
#
# 用法:
#   bash cleanup_yohaku.sh           # 保留最近 5 个版本
#   bash cleanup_yohaku.sh 3         # 保留最近 3 个版本
#   bash cleanup_yohaku.sh --dry-run # 只预览不删除
#   YOHAKU_DIR=/path/yohaku bash cleanup_yohaku.sh # 自定义目录
# ============================================================

set -u

YOHAKU_DIR="${YOHAKU_DIR:-/root/yohaku}"
KEEP="${1:-5}"
DRY_RUN=0

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  KEEP="${2:-5}"
fi

# --- 基础校验 --------------------------------------------------
if [ ! -d "$YOHAKU_DIR" ]; then
  echo "ERROR: $YOHAKU_DIR 不存在，退出"
  exit 1
fi

if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || [ "$KEEP" -lt 1 ]; then
  echo "ERROR: 保留数量必须为正整数 (got: '$KEEP')"
  exit 1
fi

# --- 收集数字版本目录 ------------------------------------------
mapfile -t VERSIONS < <(ls -d "$YOHAKU_DIR"/[0-9]* 2>/dev/null | xargs -n1 basename 2>/dev/null | grep -E '^[0-9]+$' | sort -rn)

if [ "${#VERSIONS[@]}" -eq 0 ]; then
  echo "没有找到任何数字版本目录，无需清理"
  exit 0
fi

echo "===== yohaku 版本清理 ====="
echo "目录: $YOHAKU_DIR"
echo "现有版本 (${#VERSIONS[@]} 个): ${VERSIONS[*]}"

# --- 当前软链指向的版本（绝不能删） ----------------------------
PROTECTED=()
for link in server.js public; do
  if [ -L "$YOHAKU_DIR/$link" ]; then
    tgt=$(readlink "$YOHAKU_DIR/$link")
    ver=$(echo "$tgt" | grep -oE '^[0-9]+' || true)
    if [ -n "$ver" ] && [ -d "$YOHAKU_DIR/$ver" ]; then
      PROTECTED+=("$ver")
      echo "软链 $link -> $tgt (版本 $ver 受保护)"
    fi
  fi
done

# --- 计算保留列表：最近的 KEEP 个 + 受保护版本 ------------------
KEEP_LIST=("${VERSIONS[@]:0:KEEP}")
for v in "${PROTECTED[@]}"; do
  if ! [[ " ${KEEP_LIST[*]} " =~ " $v " ]]; then
    KEEP_LIST+=("$v")
  fi
done

echo "保留版本: ${KEEP_LIST[*]}"

# --- 计算删除列表 ----------------------------------------------
DELETE_LIST=()
for v in "${VERSIONS[@]}"; do
  if ! [[ " ${KEEP_LIST[*]} " =~ " $v " ]]; then
    DELETE_LIST+=("$v")
  fi
done

if [ "${#DELETE_LIST[@]}" -eq 0 ]; then
  echo "没有需要清理的旧版本。"
  exit 0
fi

echo "待删除版本 (${#DELETE_LIST[@]} 个): ${DELETE_LIST[*]}"

# --- 预计算可释放空间 ------------------------------------------
FREED_BYTES=0
for v in "${DELETE_LIST[@]}"; do
  if [ -d "$YOHAKU_DIR/$v" ]; then
    sz=$(du -sb "$YOHAKU_DIR/$v" 2>/dev/null | awk '{print $1}')
    FREED_BYTES=$((FREED_BYTES + sz))
  fi
done
echo "预计释放: $(numfmt --to=iec "$FREED_BYTES" 2>/dev/null || echo "${FREED_BYTES} bytes")"

if [ "$DRY_RUN" = "1" ]; then
  echo "---- DRY RUN 模式，未执行任何删除 ----"
  exit 0
fi

# --- 执行删除 ---------------------------------------------------
for v in "${DELETE_LIST[@]}"; do
  if rm -rf "$YOHAKU_DIR/$v"; then
    echo "已删除: $YOHAKU_DIR/$v"
  else
    echo "ERROR: 删除失败 $YOHAKU_DIR/$v"
    exit 1
  fi
done

# --- 删除后校验 ------------------------------------------------
echo "===== 清理完成，校验 ====="
echo "剩余版本目录:"
ls -d "$YOHAKU_DIR"/[0-9]* 2>/dev/null | xargs -n1 basename 2>/dev/null | grep -E '^[0-9]+$' | sort -rn
for link in server.js public; do
  if [ -L "$YOHAKU_DIR/$link" ] && [ -e "$YOHAKU_DIR/$link" ]; then
    echo "OK: $link -> $(readlink "$YOHAKU_DIR/$link")"
  else
    echo "ERROR: $link 软链失效！站点可能已损坏"
    exit 1
  fi
done
echo "全部完成。"
