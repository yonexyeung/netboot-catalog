#!/usr/bin/env bash
# NetBoot Catalog — Container Entrypoint
# Starts: dnsmasq + nginx + file watcher

set -euo pipefail

log() { echo "[nbc-server] $*"; }

# Generate initial menu if catalog has entries
if [[ -n "$(ls -A /srv/catalog 2>/dev/null)" ]]; then
    log "Generating iPXE menu from existing catalog..."
    nbc generate --output /srv/tftp/menu.ipxe --base-url "${NBC_BASE_URL:-http://\${next-server}/catalog}"
fi

# Start dnsmasq
log "Starting dnsmasq (proxyDHCP + TFTP)..."
dnsmasq --no-daemon --log-queries &
DNSMASQ_PID=$!

# Start nginx
log "Starting nginx (HTTP)..."
nginx -g "daemon off;" &
NGINX_PID=$!

# File watcher — auto-import ISOs dropped into /srv/import
log "Watching /srv/import for new ISOs..."
inotifywait -m -e close_write -e moved_to /srv/import --format '%f' 2>/dev/null | while read -r filename; do
    if [[ "$filename" == *.iso ]]; then
        log "New ISO detected: $filename"
        if nbc import "/srv/import/$filename"; then
            log "Import successful. Regenerating menu..."
            nbc generate --output /srv/tftp/menu.ipxe --base-url "${NBC_BASE_URL}"
        else
            log "Import failed for: $filename"
        fi
    fi
done &
WATCHER_PID=$!

log "NetBoot Catalog server running."
log "  Import folder: /srv/import"
log "  Catalog:       /srv/catalog"
log "  TFTP:          port 69"
log "  HTTP:          port 80"

# Wait for any process to exit
wait -n $DNSMASQ_PID $NGINX_PID $WATCHER_PID 2>/dev/null || true
log "A service has stopped. Shutting down..."
kill $DNSMASQ_PID $NGINX_PID $WATCHER_PID 2>/dev/null || true
wait
