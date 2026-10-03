#!/bin/bash
# Distribute the 1Panel-managed cert of derper.lipiston.eu.org into the
# tailscale-derper container and refresh the OpenResty 443 entry.
# 1Panel owns issuance/renewal; this script only distributes + reloads.
set -euo pipefail
SRC_DIR=/opt/1panel/www/sites/derper.lipiston.eu.org/ssl
DST_DIR=/opt/1panel/docker/compose/tailscale-derper/data
LOG=/var/log/derper-cert-sync.log
SRC_CRT="$SRC_DIR/fullchain.pem"; SRC_KEY="$SRC_DIR/privkey.pem"
DST_CRT="$DST_DIR/derper.lipiston.eu.org.crt"; DST_KEY="$DST_DIR/derper.lipiston.eu.org.key"
log() { echo "$(date "+%F %T") $*" >> "$LOG"; }

[ -s "$SRC_CRT" ] && [ -s "$SRC_KEY" ] || { log "ERROR: 1Panel cert missing in $SRC_DIR"; exit 1; }
openssl x509 -in "$SRC_CRT" -noout -checkhost derper.lipiston.eu.org >/dev/null 2>&1 \
  || { log "ERROR: source cert does not cover derper.lipiston.eu.org - skipped"; exit 1; }
openssl x509 -in "$SRC_CRT" -noout -checkend 259200 >/dev/null 2>&1 \
  || { log "ERROR: source cert expires within 3 days - skipped"; exit 1; }

NEW=$(sha256sum "$SRC_CRT" | cut -d" " -f1)
CUR="none"; [ -f "$DST_CRT" ] && CUR=$(sha256sum "$DST_CRT" | cut -d" " -f1)
[ "$NEW" = "$CUR" ] && exit 0

install -m 644 "$SRC_CRT" "$DST_CRT"
install -m 600 "$SRC_KEY" "$DST_KEY"
docker restart tailscale-derper >/dev/null

# refresh the 443 entry (OpenResty keeps the cert in memory, so a reload is required)
OC=$(docker ps --format "{{.Names}}" | grep -i openresty | head -n1 || true)
if [ -n "$OC" ]; then
  docker exec "$OC" openresty -s reload >/dev/null 2>&1 \
    || log "ERROR: openresty reload failed in $OC - port 443 still serves the previous cert"
else
  log "ERROR: no openresty container found - port 443 still serves the previous cert"
fi

log "synced cert (sha256 ${NEW:0:16}, notAfter $(openssl x509 -in "$DST_CRT" -noout -enddate | cut -d= -f2)) -> restarted tailscale-derper + reloaded ${OC:-none}"
