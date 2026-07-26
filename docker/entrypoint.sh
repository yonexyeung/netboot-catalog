#!/usr/bin/env bash
# NetBoot Catalog — Container Entrypoint
# Starts: dnsmasq + nginx + file watcher

set -euo pipefail

log() { echo "[nbc-server] $*"; }

# Determine server IP
if [[ -z "${NBC_SERVER_IP:-}" ]]; then
    # Auto-detect: first non-loopback IPv4 address
    NBC_SERVER_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [[ -z "$NBC_SERVER_IP" ]]; then
        NBC_SERVER_IP="0.0.0.0"
        log "WARNING: Could not detect server IP. Set NBC_SERVER_IP env var."
    fi
fi
log "Server IP: $NBC_SERVER_IP"

# Set base URL
NBC_BASE_URL="${NBC_BASE_URL:-http://$NBC_SERVER_IP/catalog}"
export NBC_BASE_URL

# Patch dnsmasq config with actual IP and subnet
sed -i "s/__NBC_SERVER_IP__/$NBC_SERVER_IP/g" /etc/dnsmasq.d/nbc.conf

# Determine subnet (e.g. 192.168.50.0 from 192.168.50.160)
NBC_SUBNET="${NBC_SUBNET:-$(echo "$NBC_SERVER_IP" | sed 's/\.[0-9]*$/.0/')}"
sed -i "s/__NBC_SUBNET__/$NBC_SUBNET/g" /etc/dnsmasq.d/nbc.conf
log "Subnet: $NBC_SUBNET"

# Patch nginx to serve on correct IP (optional, default 0.0.0.0 is fine)

# Generate iPXE menu if catalog has entries
if [[ -n "$(ls -A /srv/catalog 2>/dev/null)" ]]; then
    log "Generating iPXE menu from existing catalog..."
    nbc generate --output /srv/tftp/menu.ipxe --base-url "$NBC_BASE_URL"
    
    # Symlink catalog entries into TFTP root for kernel/initrd delivery
    # (iPXE image trust blocks HTTP but allows TFTP)
    ln -sfn /srv/catalog /srv/tftp/catalog
fi

# Start dnsmasq
log "Starting dnsmasq (proxyDHCP + TFTP)..."
dnsmasq --no-daemon --conf-file=/etc/dnsmasq.d/nbc.conf &
DNSMASQ_PID=$!

# Start nginx (as root to access catalog files owned by root)
log "Starting nginx (HTTP)..."
nginx -g "daemon off; user root;" &
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
