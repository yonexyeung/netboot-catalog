#!/usr/bin/env bash
# pve-install.sh — Proxmox VE Helper Script for NetBoot Catalog
# 
# Creates a Debian 13 LXC container with Docker, then deploys netboot-catalog.
# Run this on your Proxmox VE host (not inside a container).
#
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/yonexyeung/netboot-catalog/main/scripts/pve-install.sh)"
#
# Requirements:
#   - Proxmox VE 8+
#   - Internet access (to download CT template + Docker image)
#   - Available CT ID

set -euo pipefail

# --- Defaults ---
APP="NetBoot-Catalog"
CT_ID="${CT_ID:-}"
CT_HOSTNAME="${CT_HOSTNAME:-netboot-catalog}"
CT_DISK="${CT_DISK:-8}"
CT_RAM="${CT_RAM:-2048}"
CT_CPU="${CT_CPU:-2}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
CT_STORAGE="${CT_STORAGE:-local-lvm}"
CT_TEMPLATE_STORAGE="${CT_TEMPLATE_STORAGE:-local}"
CT_OS="debian"
CT_VERSION="13"
NBC_REPO="https://github.com/yonexyeung/netboot-catalog.git"

# --- Colors ---
GN='\033[0;32m'
YW='\033[0;33m'
RD='\033[0;31m'
NC='\033[0m'

info() { echo -e "${YW}[info]${NC} $*"; }
ok()   { echo -e "${GN}[ok]${NC} $*"; }
err()  { echo -e "${RD}[error]${NC} $*"; exit 1; }

# --- Pre-flight ---
[[ -f /etc/pve/.version ]] || err "This script must be run on a Proxmox VE host."
command -v pct >/dev/null || err "pct not found. Are you on a Proxmox host?"

echo ""
echo -e "${GN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GN}║       NetBoot Catalog Installer          ║${NC}"
echo -e "${GN}║  Drop ISO. Network Boot. Open Source.    ║${NC}"
echo -e "${GN}╚══════════════════════════════════════════╝${NC}"
echo ""

# --- Get next available CT ID ---
if [[ -z "$CT_ID" ]]; then
    CT_ID=$(pvesh get /cluster/nextid)
fi
info "Container ID: $CT_ID"

# --- Prompt for settings ---
read -r -p "  Hostname [${CT_HOSTNAME}]: " input
CT_HOSTNAME="${input:-$CT_HOSTNAME}"

read -r -p "  Disk size GB [${CT_DISK}]: " input
CT_DISK="${input:-$CT_DISK}"

read -r -p "  RAM MB [${CT_RAM}]: " input
CT_RAM="${input:-$CT_RAM}"

read -r -p "  CPU cores [${CT_CPU}]: " input
CT_CPU="${input:-$CT_CPU}"

read -r -p "  Network bridge [${CT_BRIDGE}]: " input
CT_BRIDGE="${input:-$CT_BRIDGE}"

read -r -p "  Storage [${CT_STORAGE}]: " input
CT_STORAGE="${input:-$CT_STORAGE}"

echo ""
info "Creating LXC: ID=$CT_ID, Host=$CT_HOSTNAME, Disk=${CT_DISK}G, RAM=${CT_RAM}MB, CPU=$CT_CPU"
echo ""
read -r -p "  Proceed? [Y/n]: " confirm
if [[ "${confirm,,}" == "n" ]]; then
    echo "Aborted."
    exit 0
fi

# --- Download CT template ---
info "Downloading Debian ${CT_VERSION} template..."
TEMPLATE="debian-${CT_VERSION}-standard_${CT_VERSION}.0-1_amd64.tar.zst"

# Check if template already exists
if ! pveam list "$CT_TEMPLATE_STORAGE" | grep -q "$CT_OS-${CT_VERSION}"; then
    pveam update >/dev/null 2>&1
    TEMPLATE_FULL=$(pveam available --section system | grep "debian-${CT_VERSION}" | tail -1 | awk '{print $2}')
    if [[ -z "$TEMPLATE_FULL" ]]; then
        err "Debian ${CT_VERSION} template not found. Run: pveam update"
    fi
    pveam download "$CT_TEMPLATE_STORAGE" "$TEMPLATE_FULL" >/dev/null 2>&1
    ok "Template downloaded: $TEMPLATE_FULL"
else
    TEMPLATE_FULL=$(pveam list "$CT_TEMPLATE_STORAGE" | grep "debian-${CT_VERSION}" | tail -1 | awk '{print $1}')
    ok "Template already available: $TEMPLATE_FULL"
fi

# --- Create container ---
info "Creating container..."
pct create "$CT_ID" "$TEMPLATE_FULL" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CT_CPU" \
    --memory "$CT_RAM" \
    --rootfs "${CT_STORAGE}:${CT_DISK}" \
    --net0 "name=eth0,bridge=${CT_BRIDGE},ip=dhcp" \
    --ostype debian \
    --unprivileged 1 \
    --features nesting=1,keyctl=1 \
    --onboot 1 \
    --start 0 \
    >/dev/null 2>&1
ok "Container $CT_ID created"

# --- Start container ---
info "Starting container..."
pct start "$CT_ID"
sleep 5
ok "Container started"

# --- Wait for network ---
info "Waiting for network..."
for i in $(seq 1 30); do
    if pct exec "$CT_ID" -- ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
ok "Network ready"

# --- Install Docker inside container ---
info "Installing Docker..."
pct exec "$CT_ID" -- bash -c '
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg git
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
' >/dev/null 2>&1
ok "Docker installed"

# --- Clone and deploy NetBoot Catalog ---
info "Deploying NetBoot Catalog..."
pct exec "$CT_ID" -- bash -c "
    git clone ${NBC_REPO} /opt/netboot-catalog
    cd /opt/netboot-catalog
    docker compose build
    mkdir -p /srv/import /srv/catalog
    docker compose up -d
" >/dev/null 2>&1
ok "NetBoot Catalog deployed"

# --- Get container IP ---
CT_IP=$(pct exec "$CT_ID" -- bash -c "ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'" 2>/dev/null || echo "DHCP")

# --- Done ---
echo ""
echo -e "${GN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GN}║    NetBoot Catalog — Ready!              ║${NC}"
echo -e "${GN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Container ID:  ${GN}${CT_ID}${NC}"
echo -e "  Hostname:      ${GN}${CT_HOSTNAME}${NC}"
echo -e "  IP Address:    ${GN}${CT_IP}${NC}"
echo -e "  Health Check:  ${GN}http://${CT_IP}/health${NC}"
echo -e "  iPXE Menu:     ${GN}http://${CT_IP}/tftp/menu.ipxe${NC}"
echo ""
echo -e "  Import ISOs:   ${YW}pct exec ${CT_ID} -- nbc import /srv/import/<file>.iso${NC}"
echo -e "  List Catalog:  ${YW}pct exec ${CT_ID} -- nbc list${NC}"
echo -e "  View Logs:     ${YW}pct exec ${CT_ID} -- docker compose -f /opt/netboot-catalog/docker-compose.yml logs${NC}"
echo ""
echo -e "  Drop ISOs into ${YW}/srv/import/${NC} inside the container for auto-import."
echo ""
