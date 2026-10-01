#!/usr/bin/env bash
# TeamSpeak 3 Server 安装脚本（Ubuntu 22.04+，原生部署到 /opt/teamspeak3）
# 用法：sudo TS_VER=3.13.8 bash install_teamspeak3.sh
# 幂等：已存在 /opt/teamspeak3/ts3server 时跳过下载解包，只重写配置与 unit 并重启。
set -euo pipefail

TS_VER="${TS_VER:-3.13.8}"
BASE=/opt/teamspeak3
INI="$BASE/ts3server.ini"
TARBALL="/tmp/teamspeak3-server_linux_amd64-${TS_VER}.tar.bz2"
URL="https://files.teamspeak-services.com/releases/server/${TS_VER}/teamspeak3-server_linux_amd64-${TS_VER}.tar.bz2"

echo "== 1. 磁盘检查 =="
df -h / | tail -1

echo "== 2. 下载并解包 =="
if [ -x "$BASE/ts3server" ]; then
  echo "已存在 $BASE/ts3server，跳过下载"
else
  curl -fL --retry 3 --retry-delay 2 -o "$TARBALL" "$URL"
  ls -lh "$TARBALL"
  mkdir -p "$BASE"
  tar -xjf "$TARBALL" -C "$BASE" --strip-components=1
  rm -f "$TARBALL"
fi
ls "$BASE" | head -20

echo "== 3. 运行用户 =="
id -u teamspeak >/dev/null 2>&1 || useradd -r -M -d "$BASE" -s /usr/sbin/nologin teamspeak
id teamspeak

echo "== 4. 配置文件 =="
[ -f "$INI" ] && cp "$INI" "$INI.bak-$(date +%Y%m%d-%H%M%S)"
cat > "$INI" <<'EOF'
# TeamSpeak 3 Server 配置
licensepath=
default_voice_port=9987
voice_ip=0.0.0.0
filetransfer_port=30033
filetransfer_ip=0.0.0.0
query_port=10011
query_ip=127.0.0.1
query_ip_allowlist=query_ip_whitelist.txt
query_ip_denylist=query_ip_blacklist.txt
dbplugin=ts3db_sqlite3
dbpluginparameter=ts3db_sqlite3.ini
dbsqlpath=sql/
dbsqlcreatepath=create_sqlite/
logpath=logs
logquerycommands=0
dbclientkeepdays=90
logappend=0
EOF
[ -f "$BASE/query_ip_whitelist.txt" ] || printf '127.0.0.1\n::1\n' > "$BASE/query_ip_whitelist.txt"

echo "== 5. 许可接受标记 + 权限 =="
touch "$BASE/.ts3server_license_accepted"
chown -R teamspeak:teamspeak "$BASE"
chmod 600 "$INI"

echo "== 6. systemd 服务 =="
cat > /etc/systemd/system/teamspeak3.service <<'EOF'
[Unit]
Description=TeamSpeak 3 Server
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=teamspeak
Group=teamspeak
WorkingDirectory=/opt/teamspeak3
ExecStart=/opt/teamspeak3/ts3server_startscript.sh start inifile=ts3server.ini
ExecStop=/opt/teamspeak3/ts3server_startscript.sh stop
ExecReload=/opt/teamspeak3/ts3server_startscript.sh restart
PIDFile=/opt/teamspeak3/ts3server.pid
Restart=always
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable teamspeak3 >/dev/null 2>&1
systemctl restart teamspeak3
sleep 6

echo "== 7. 状态 =="
systemctl is-active teamspeak3
echo "--- 监听端口 ---"
ss -tulnp | grep -E "9987|30033|10011" || echo "!! 未发现监听端口"

echo "== 8. 日志文件 =="
ls -t "$BASE"/logs/ts3server_*.log 2>/dev/null | head -3
echo "首次安装时，ServerAdmin 特权密钥在 *_1.log 里（token=...），仅显示一次。"
