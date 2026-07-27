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

# Patch dnsmasq config with subnet
NBC_SUBNET="${NBC_SUBNET:-$(echo "$NBC_SERVER_IP" | sed 's/\.[0-9]*$/.0/')}"
sed -i "s/__NBC_SUBNET__/$NBC_SUBNET/g" /etc/dnsmasq.d/nbc.conf
log "Subnet: $NBC_SUBNET"

# Patch nginx to serve on correct IP (optional, default 0.0.0.0 is fine)

# Symlink catalog into TFTP root (always, even if empty now — imports happen later)
ln -sfn /srv/catalog /srv/tftp/catalog

# Generate iPXE menu if catalog has entries
if [[ -n "$(ls -A /srv/catalog 2>/dev/null)" ]]; then
    log "Generating iPXE menu from existing catalog..."
    nbc generate --output /srv/tftp/menu.ipxe --base-url "$NBC_BASE_URL"
fi

# Start dnsmasq
log "Starting dnsmasq (proxyDHCP + TFTP)..."
dnsmasq --no-daemon --conf-file=/etc/dnsmasq.d/nbc.conf &
DNSMASQ_PID=$!

# Ensure catalog files are readable by nginx (www-data)
# If volume is read-only, this is a no-op (permissions should be set at import time)
chmod -R o+rX /srv/catalog 2>/dev/null || true

# Start nginx
log "Starting nginx (HTTP)..."
nginx -g "daemon off;" &
NGINX_PID=$!

# File watcher — auto-import ISOs dropped into /srv/import
# Uses both inotifywait (instant for in-container writes) and polling (for pct push / external writes)
log "Watching /srv/import for new ISOs..."
IMPORT_TRACKER="/var/tmp/nbc-imported.list"
touch "$IMPORT_TRACKER"

import_iso() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    local lockfile="/var/tmp/nbc-import.lock"
    
    # Skip if already imported
    if grep -qxF "$filename" "$IMPORT_TRACKER" 2>/dev/null; then
        return
    fi
    
    # Lock to prevent concurrent import of same file
    if ! mkdir "$lockfile" 2>/dev/null; then
        return  # Another import in progress
    fi
    trap "rmdir '$lockfile' 2>/dev/null" RETURN
    
    # Double-check after acquiring lock
    if grep -qxF "$filename" "$IMPORT_TRACKER" 2>/dev/null; then
        return
    fi
    
    log "New ISO detected: $filename"
    if nbc import "$filepath"; then
        echo "$filename" >> "$IMPORT_TRACKER"
        log "Import successful."
    else
        log "Import failed for: $filename"
    fi
}

# inotifywait for in-container file creation (instant)
inotifywait -m -e close_write -e moved_to /srv/import --format '%f' 2>/dev/null | while read -r filename; do
    if [[ "$filename" == *.iso ]]; then
        import_iso "/srv/import/$filename"
    fi
done &
WATCHER_PID=$!

# Polling fallback for files written externally (pct push, NFS, etc.)
(
    while true; do
        sleep 10
        for iso in /srv/import/*.iso; do
            [[ -f "$iso" ]] || continue
            import_iso "$iso"
        done
    done
) &
POLL_PID=$!

log "NetBoot Catalog server running."
log "  Import folder: /srv/import"
log "  Catalog:       /srv/catalog"
log "  TFTP:          port 69"
log "  HTTP:          port 80"

# Wait for any process to exit
wait -n $DNSMASQ_PID $NGINX_PID $WATCHER_PID $POLL_PID 2>/dev/null || true
log "A service has stopped. Shutting down..."
kill $DNSMASQ_PID $NGINX_PID $WATCHER_PID $POLL_PID 2>/dev/null || true
wait
