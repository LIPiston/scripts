#!/bin/bash
# 作者 LIPiston
# 作用 rime sync 同步脚本，适用于 Android 平台（Termux 或 Magisk 模块环境）
# 或许需要root权限运行
#
# --- 基础配置 ---
RCLONE_CONF="/data/adb/modules/rclone/conf/rclone.conf"  # <--- 在这里填入 rclone.conf 文件绝对路径
LOCAL_A="/storage/emulated/0/Android/data/org.fcitx.fcitx5.android/files/data/rime/sync" #本地sync文件夹绝对路径
REMOTE_NAME="webdav" #远程名称
REMOTE_A="rimesync" #远程文件夹
FOLDER_B="oneplus7" #本机设备文件夹，即 installation.yaml 里写的名称

# --- 检查配置文件是否存在 ---
if [ ! -f "$RCLONE_CONF" ]; then
    echo "错误: 找不到配置文件 $RCLONE_CONF"
    exit 1
fi

# 定义基础命令，减少重复输入
RCLONE_CMD="rclone --config $RCLONE_CONF"

# --- 第一步：上传 B 文件夹 ---
echo "Step 1: 正在上传本地 $FOLDER_B 到远程..."
$RCLONE_CMD copy "$LOCAL_A/$FOLDER_B" "$REMOTE_NAME:$REMOTE_A/$FOLDER_B" --progress

# --- 第二步：拉取远程 A 中除去 B 以外的内容 ---
echo "Step 2: 正在拉取远程文件（排除 $FOLDER_B）..."
# 注意：--exclude 后的路径是相对于 REMOTE_A 的
$RCLONE_CMD copy "$REMOTE_NAME:$REMOTE_A" "$LOCAL_A" \
    --exclude "/$FOLDER_B/**" \
    --progress

echo "任务全部完成！"
