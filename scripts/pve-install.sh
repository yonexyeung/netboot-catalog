#!/usr/bin/env bash
# pve-install.sh — Proxmox VE Helper Script for NetBoot Catalog
#
# Creates a Debian 13 LXC with Docker and deploys netboot-catalog.
# Features whiptail GUI with auto-detection of host storage, bridges, and VLANs.
#
# Run on Proxmox VE host:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/yonexyeung/netboot-catalog/main/scripts/pve-install.sh)"

set -euo pipefail

# --- Configuration ---
APP="NetBoot Catalog"
APP_REPO="https://github.com/yonexyeung/netboot-catalog.git"
CT_OS="debian"
CT_VERSION="13"

# --- Colors ---
GN='\033[0;32m'
YW='\033[0;33m'
RD='\033[0;31m'
BL='\033[0;34m'
NC='\033[0m'

info() { echo -e "${YW}[info]${NC} $*"; }
ok()   { echo -e "${GN}[✓]${NC} $*"; }
err()  { echo -e "${RD}[✗]${NC} $*" >&2; exit 1; }

# --- Pre-flight checks ---
[[ $EUID -eq 0 ]] || err "Must run as root"
[[ -f /etc/pve/.version ]] || [[ -d /etc/pve ]] || err "This script must be run on a Proxmox VE host."
command -v pct >/dev/null || err "pct not found."
command -v whiptail >/dev/null || apt-get install -y whiptail >/dev/null 2>&1

# --- Helper: get available storages ---
get_storages() {
    local type="$1" # "rootdir" or "images" or "vztmpl"
    pvesm status --content "$type" 2>/dev/null | awk 'NR>1 && $2=="active" {print $1}' | sort
}

# --- Helper: get available bridges ---
get_bridges() {
    ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | sort
}

# --- Helper: whiptail menu from list ---
select_from_list() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")
    local menu_items=()

    for item in "${items[@]}"; do
        menu_items+=("$item" "" "OFF")
    done
    # Set first item ON
    if [[ ${#menu_items[@]} -ge 3 ]]; then
        menu_items[2]="ON"
    fi

    whiptail --title "$title" --radiolist "$prompt" 16 60 8 "${menu_items[@]}" 3>&1 1>&2 2>&3 || echo "${items[0]}"
}

# --- Header ---
whiptail --title "NetBoot Catalog" --msgbox \
"Drop ISO. Network Boot. Open Source.

This script will create a Debian 13 LXC container with Docker
and deploy NetBoot Catalog for PXE network booting.

Requirements:
  - Available storage for CT rootfs
  - Available storage for CT templates
  - Network bridge for PXE traffic" 16 60

# --- Get next CT ID ---
CT_ID=$(pvesh get /cluster/nextid)
CT_ID=$(whiptail --title "Container ID" --inputbox "Enter CT ID:" 8 40 "$CT_ID" 3>&1 1>&2 2>&3) || exit

# --- Hostname ---
CT_HOSTNAME=$(whiptail --title "Hostname" --inputbox "Enter hostname:" 8 40 "netboot-catalog" 3>&1 1>&2 2>&3) || exit

# --- Select rootfs storage ---
ROOTFS_STORAGES=($(get_storages "rootdir"))
if [[ ${#ROOTFS_STORAGES[@]} -eq 0 ]]; then
    # Fallback: try images content type
    ROOTFS_STORAGES=($(get_storages "images"))
fi
if [[ ${#ROOTFS_STORAGES[@]} -eq 0 ]]; then
    err "No active storage found for container rootfs"
fi

if [[ ${#ROOTFS_STORAGES[@]} -eq 1 ]]; then
    CT_STORAGE="${ROOTFS_STORAGES[0]}"
else
    CT_STORAGE=$(select_from_list "Root Storage" "Select storage for container rootfs:" "${ROOTFS_STORAGES[@]}")
fi

# --- Select template storage ---
TPL_STORAGES=($(get_storages "vztmpl"))
if [[ ${#TPL_STORAGES[@]} -eq 0 ]]; then
    err "No active storage found for CT templates (vztmpl)"
fi

if [[ ${#TPL_STORAGES[@]} -eq 1 ]]; then
    CT_TPL_STORAGE="${TPL_STORAGES[0]}"
else
    CT_TPL_STORAGE=$(select_from_list "Template Storage" "Select storage for CT templates:" "${TPL_STORAGES[@]}")
fi

# --- Disk size ---
CT_DISK=$(whiptail --title "Disk Size" --inputbox "Root disk size (GB):" 8 40 "8" 3>&1 1>&2 2>&3) || exit

# --- RAM ---
CT_RAM=$(whiptail --title "Memory" --inputbox "RAM (MB):" 8 40 "2048" 3>&1 1>&2 2>&3) || exit

# --- CPU ---
CT_CPU=$(whiptail --title "CPU Cores" --inputbox "CPU cores:" 8 40 "2" 3>&1 1>&2 2>&3) || exit

# --- Select network bridge ---
BRIDGES=($(get_bridges))
if [[ ${#BRIDGES[@]} -eq 0 ]]; then
    BRIDGES=("vmbr0")
fi

if [[ ${#BRIDGES[@]} -eq 1 ]]; then
    CT_BRIDGE="${BRIDGES[0]}"
else
    CT_BRIDGE=$(select_from_list "Network Bridge" "Select bridge for PXE network:" "${BRIDGES[@]}")
fi

# --- VLAN tag (optional) ---
CT_VLAN=$(whiptail --title "VLAN Tag" --inputbox "VLAN tag (leave empty for none):" 8 40 "" 3>&1 1>&2 2>&3) || CT_VLAN=""

# --- IP config ---
IP_MODE=$(whiptail --title "IP Configuration" --radiolist "Select IP mode:" 10 50 3 \
    "dhcp" "DHCP (automatic)" "ON" \
    "static" "Static IP" "OFF" \
    3>&1 1>&2 2>&3) || IP_MODE="dhcp"

CT_IP_CONFIG="ip=dhcp"
if [[ "$IP_MODE" == "static" ]]; then
    STATIC_IP=$(whiptail --title "Static IP" --inputbox "IP address (CIDR, e.g. 192.168.50.200/24):" 8 50 "" 3>&1 1>&2 2>&3) || exit
    STATIC_GW=$(whiptail --title "Gateway" --inputbox "Gateway:" 8 50 "" 3>&1 1>&2 2>&3) || exit
    CT_IP_CONFIG="ip=${STATIC_IP},gw=${STATIC_GW}"
fi

# --- Network string ---
NET_CONFIG="name=eth0,bridge=${CT_BRIDGE}"
if [[ -n "$CT_VLAN" ]]; then
    NET_CONFIG="${NET_CONFIG},tag=${CT_VLAN}"
fi

# --- Confirmation ---
SUMMARY="Container ID:   ${CT_ID}
Hostname:       ${CT_HOSTNAME}
Storage:        ${CT_STORAGE}
Template Store: ${CT_TPL_STORAGE}
Disk:           ${CT_DISK} GB
RAM:            ${CT_RAM} MB
CPU:            ${CT_CPU} cores
Bridge:         ${CT_BRIDGE}
VLAN:           ${CT_VLAN:-none}
IP:             ${IP_MODE}
"

whiptail --title "Confirm Settings" --yesno "$SUMMARY\nProceed with installation?" 18 50 || exit

# --- Download CT template ---
info "Downloading Debian ${CT_VERSION} template..."
pveam update >/dev/null 2>&1 || true
TEMPLATE_FULL=$(pveam available --section system | grep "debian-${CT_VERSION}" | tail -1 | awk '{print $2}')
if [[ -z "$TEMPLATE_FULL" ]]; then
    err "Debian ${CT_VERSION} template not found in available list."
fi

if ! pveam list "$CT_TPL_STORAGE" | grep -q "$(basename "$TEMPLATE_FULL")"; then
    pveam download "$CT_TPL_STORAGE" "$TEMPLATE_FULL"
fi
TEMPLATE_PATH="${CT_TPL_STORAGE}:vztmpl/$(basename "$TEMPLATE_FULL")"
ok "Template ready: $TEMPLATE_PATH"

# --- Create container ---
info "Creating container ${CT_ID}..."
pct create "$CT_ID" "$TEMPLATE_PATH" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CT_CPU" \
    --memory "$CT_RAM" \
    --rootfs "${CT_STORAGE}:${CT_DISK}" \
    --net0 "${NET_CONFIG},${CT_IP_CONFIG}" \
    --ostype debian \
    --unprivileged 1 \
    --features nesting=1,keyctl=1 \
    --onboot 1 \
    --start 0
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

# --- Install Docker ---
info "Installing Docker (this may take 1-2 minutes)..."
pct exec "$CT_ID" -- bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg git >/dev/null 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
'
ok "Docker installed"

# --- Deploy NetBoot Catalog ---
info "Deploying NetBoot Catalog..."
pct exec "$CT_ID" -- bash -c "
    git clone ${APP_REPO} /opt/netboot-catalog >/dev/null 2>&1
    cd /opt/netboot-catalog
    docker compose build >/dev/null 2>&1
    mkdir -p /srv/import /srv/catalog
    docker compose up -d >/dev/null 2>&1
"
ok "NetBoot Catalog deployed"

# --- Get container IP ---
sleep 3
CT_IP=$(pct exec "$CT_ID" -- bash -c "ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}'" || echo "unknown")

# --- Done ---
clear
echo ""
echo -e "${GN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GN}║     NetBoot Catalog — Installation Complete  ║${NC}"
echo -e "${GN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Container ID:   ${GN}${CT_ID}${NC}"
echo -e "  Hostname:       ${GN}${CT_HOSTNAME}${NC}"
echo -e "  IP Address:     ${GN}${CT_IP}${NC}"
echo ""
echo -e "  ${BL}Health Check:${NC}   curl http://${CT_IP}/health"
echo -e "  ${BL}iPXE Menu:${NC}      http://${CT_IP}/tftp/menu.ipxe"
echo ""
echo -e "  ${YW}Import ISO:${NC}     pct exec ${CT_ID} -- nbc import /srv/import/<file>.iso"
echo -e "  ${YW}List Catalog:${NC}   pct exec ${CT_ID} -- nbc list"
echo -e "  ${YW}View Logs:${NC}      pct exec ${CT_ID} -- docker logs nbc"
echo ""
echo -e "  Drop ISOs into ${YW}/srv/import/${NC} inside the container for auto-import."
echo ""
