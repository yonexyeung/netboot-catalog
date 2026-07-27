#!/usr/bin/env bash
# pve-install.sh — Proxmox VE Helper Script for NetBoot Catalog
#
# Creates a Debian 13 LXC with Docker and deploys netboot-catalog.
# Features whiptail GUI with auto-detection of host storage, bridges, and VLANs.
#
# NOTE: This is a standalone script. It does NOT use community-scripts build.func
# because build.func hardcodes its install script URL to the community-scripts repo.
# We replicate the key UX patterns (whiptail, storage detection) independently.
#
# Run on Proxmox VE host:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/yonexyeung/netboot-catalog/main/scripts/pve-install.sh)"

set -euo pipefail

APP="NetBoot Catalog"
APP_REPO="https://github.com/yonexyeung/netboot-catalog.git"

# --- Pre-flight ---
[[ $EUID -eq 0 ]] || { echo "ERROR: Must run as root."; exit 1; }
[[ -d /etc/pve ]] || { echo "ERROR: This script must be run on a Proxmox VE host."; exit 1; }
command -v pct >/dev/null || { echo "ERROR: pct not found."; exit 1; }
command -v whiptail >/dev/null || apt-get install -y -qq whiptail >/dev/null 2>&1

# --- Colors ---
GN='\033[0;32m'; YW='\033[0;33m'; RD='\033[0;31m'; BL='\033[0;34m'; NC='\033[0m'
BFR='\r\033[K'; CM="${GN}✓${NC}"; HOLD="${YW}⏳${NC}"

msg_info() { echo -ne "${HOLD} ${YW}${1}${NC}"; }
msg_ok()   { echo -e "${BFR}${CM} ${GN}${1}${NC}"; }
msg_err()  { echo -e "${BFR}${RD}✗ ${1}${NC}"; exit 1; }

# --- Helpers: detect available resources ---

get_rootdir_storages() {
    # Storages that support rootdir or images content (from storage.cfg)
    local stores=()
    local current_store=""
    local is_active=true
    while IFS= read -r line; do
        # New storage block (e.g. "btrfs: local-btrfs" or "dir: local")
        if [[ "$line" =~ ^[a-z]+:\ (.+)$ ]]; then
            current_store="${BASH_REMATCH[1]}"
            is_active=true
        elif [[ "$line" =~ ^[[:space:]]+disable$ ]]; then
            is_active=false
        elif [[ "$line" =~ ^[[:space:]]+content[[:space:]]+(.+)$ ]] && $is_active; then
            local content="${BASH_REMATCH[1]}"
            if echo "$content" | grep -qE "(rootdir|images)"; then
                stores+=("$current_store")
            fi
        fi
    done < /etc/pve/storage.cfg
    echo "${stores[@]}"
}

get_vztmpl_storages() {
    # Storages that support vztmpl content
    local stores=()
    local current_store=""
    local is_active=true
    while IFS= read -r line; do
        if [[ "$line" =~ ^[a-z]+:\ (.+)$ ]]; then
            current_store="${BASH_REMATCH[1]}"
            is_active=true
        elif [[ "$line" =~ ^[[:space:]]+disable$ ]]; then
            is_active=false
        elif [[ "$line" =~ ^[[:space:]]+content[[:space:]]+(.+)$ ]] && $is_active; then
            local content="${BASH_REMATCH[1]}"
            if echo "$content" | grep -q "vztmpl"; then
                stores+=("$current_store")
            fi
        fi
    done < /etc/pve/storage.cfg
    echo "${stores[@]}"
}

get_bridges() {
    # All network bridges on this host
    ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | sort
}

whiptail_select() {
    # Generic whiptail radiolist from array
    # Usage: whiptail_select "Title" "Prompt" item1 item2 item3 ...
    local title="$1" prompt="$2"
    shift 2
    local items=("$@")
    local menu_args=()
    local first=true
    for item in "${items[@]}"; do
        if $first; then
            menu_args+=("$item" "" "ON")
            first=false
        else
            menu_args+=("$item" "" "OFF")
        fi
    done
    whiptail --title "$title" --radiolist "$prompt\n\nUse SPACE to select, ENTER to confirm." \
        16 60 8 "${menu_args[@]}" 3>&1 1>&2 2>&3
}

# === MAIN ===

# Welcome
whiptail --title "$APP" --msgbox \
"Drop ISO. Network Boot. Open Source.

This script will:
  1. Create a Debian 13 LXC container
  2. Install Docker inside it
  3. Deploy NetBoot Catalog
  4. Start the PXE boot service

Your existing DHCP server will NOT be replaced.
NetBoot Catalog uses ProxyDHCP mode." 16 60

# --- CT ID ---
NEXTID=$(pvesh get /cluster/nextid)
CT_ID=$(whiptail --title "Container ID" --inputbox "Container ID:" 8 40 "$NEXTID" 3>&1 1>&2 2>&3) || exit 0

# --- Hostname ---
CT_HOSTNAME=$(whiptail --title "Hostname" --inputbox "Hostname:" 8 40 "netboot-catalog" 3>&1 1>&2 2>&3) || exit 0

# --- Root Storage ---
ROOTFS_STORES=($(get_rootdir_storages))
if [[ ${#ROOTFS_STORES[@]} -eq 0 ]]; then
    msg_err "No active storage found that supports rootdir/images content."
fi
if [[ ${#ROOTFS_STORES[@]} -eq 1 ]]; then
    CT_STORAGE="${ROOTFS_STORES[0]}"
else
    CT_STORAGE=$(whiptail_select "Root Disk Storage" "Select storage for container root disk:" "${ROOTFS_STORES[@]}") || exit 0
fi

# --- Template Storage ---
TPL_STORES=($(get_vztmpl_storages))
if [[ ${#TPL_STORES[@]} -eq 0 ]]; then
    msg_err "No active storage found that supports vztmpl content."
fi
if [[ ${#TPL_STORES[@]} -eq 1 ]]; then
    CT_TPL_STORAGE="${TPL_STORES[0]}"
else
    CT_TPL_STORAGE=$(whiptail_select "Template Storage" "Select storage for CT templates:" "${TPL_STORES[@]}") || exit 0
fi

# --- Disk / RAM / CPU ---
CT_DISK=$(whiptail --title "Disk Size" --inputbox "Root disk (GB):" 8 40 "10" 3>&1 1>&2 2>&3) || exit 0
CT_RAM=$(whiptail --title "Memory" --inputbox "RAM (MB):" 8 40 "2048" 3>&1 1>&2 2>&3) || exit 0
CT_CPU=$(whiptail --title "CPU" --inputbox "CPU cores:" 8 40 "2" 3>&1 1>&2 2>&3) || exit 0

# --- Network Bridge ---
BRIDGES=($(get_bridges))
[[ ${#BRIDGES[@]} -eq 0 ]] && BRIDGES=("vmbr0")
if [[ ${#BRIDGES[@]} -eq 1 ]]; then
    CT_BRIDGE="${BRIDGES[0]}"
else
    CT_BRIDGE=$(whiptail_select "Network Bridge" "Select bridge (PXE traffic):" "${BRIDGES[@]}") || exit 0
fi

# --- VLAN ---
CT_VLAN=$(whiptail --title "VLAN (optional)" --inputbox "VLAN tag (empty = none):" 8 40 "" 3>&1 1>&2 2>&3) || CT_VLAN=""

# --- IP ---
if whiptail --title "IP Configuration" --yesno "Use DHCP?\n\nSelect No for static IP." 10 40; then
    CT_NET_IP="ip=dhcp"
else
    STATIC_IP=$(whiptail --title "Static IP" --inputbox "IP (CIDR, e.g. 192.168.50.200/24):" 8 50 "" 3>&1 1>&2 2>&3) || exit 0
    STATIC_GW=$(whiptail --title "Gateway" --inputbox "Gateway:" 8 50 "" 3>&1 1>&2 2>&3) || exit 0
    CT_NET_IP="ip=${STATIC_IP},gw=${STATIC_GW}"
fi

# --- Password ---
CT_PASSWORD=$(whiptail --title "Root Password" --passwordbox "Set root password for container:" 8 50 3>&1 1>&2 2>&3) || exit 0
if [[ -z "$CT_PASSWORD" ]]; then
    CT_PASSWORD=$(openssl rand -base64 12)
    GENERATED_PW=true
else
    GENERATED_PW=false
fi

# --- SSH Public Key ---
CT_SSH_KEY=""
if whiptail --title "SSH Public Key" --yesno "Add SSH public key for root access?" 8 50; then
    CT_SSH_KEY=$(whiptail --title "SSH Public Key" --inputbox "Paste your public key:" 10 70 "" 3>&1 1>&2 2>&3) || CT_SSH_KEY=""
fi

# --- SSH Service ---
ENABLE_SSH=false
if whiptail --title "SSH Service" --yesno "Enable SSH service in container?\n\n(Allows remote access via ssh root@<IP>)" 10 50; then
    ENABLE_SSH=true
fi

# --- Build net string ---
NET_STR="name=eth0,bridge=${CT_BRIDGE}"
[[ -n "$CT_VLAN" ]] && NET_STR="${NET_STR},tag=${CT_VLAN}"
NET_STR="${NET_STR},${CT_NET_IP}"

# --- Confirm ---
whiptail --title "Confirm" --yesno "
Container ID:   ${CT_ID}
Hostname:       ${CT_HOSTNAME}
Storage:        ${CT_STORAGE}
Template Store: ${CT_TPL_STORAGE}
Disk:           ${CT_DISK} GB
RAM:            ${CT_RAM} MB
CPU:            ${CT_CPU} cores
Bridge:         ${CT_BRIDGE}
VLAN:           ${CT_VLAN:-none}
IP:             ${CT_NET_IP}

Create container and install ${APP}?" 20 50 || exit 0

# === Installation ===
echo ""

# Step 1: Download template
msg_info "Downloading Debian 13 template"
pveam update >/dev/null 2>&1 || true
TPL_FILE=$(pveam available --section system | grep "debian-13" | tail -1 | awk '{print $2}')
[[ -z "$TPL_FILE" ]] && msg_err "Debian 13 template not available. Run: pveam update"
if ! pveam list "$CT_TPL_STORAGE" 2>/dev/null | grep -q "$(basename "$TPL_FILE")"; then
    pveam download "$CT_TPL_STORAGE" "$TPL_FILE" >/dev/null 2>&1
fi
TPL_PATH="${CT_TPL_STORAGE}:vztmpl/$(basename "$TPL_FILE")"
msg_ok "Template ready"

# Step 2: Create container
msg_info "Creating LXC ${CT_ID}"
PCT_OPTS=(
    --hostname "$CT_HOSTNAME"
    --cores "$CT_CPU"
    --memory "$CT_RAM"
    --rootfs "${CT_STORAGE}:${CT_DISK}"
    --net0 "$NET_STR"
    --ostype debian
    --unprivileged 1
    --features nesting=1,keyctl=1
    --onboot 1
    --tags "netboot;pxe;docker"
    --start 0
)
[[ -n "$CT_PASSWORD" ]] && PCT_OPTS+=(--password "$CT_PASSWORD")
if [[ -n "$CT_SSH_KEY" ]]; then
    SSH_KEY_FILE=$(mktemp)
    echo "$CT_SSH_KEY" > "$SSH_KEY_FILE"
    PCT_OPTS+=(--ssh-public-keys "$SSH_KEY_FILE")
fi
pct create "$CT_ID" "$TPL_PATH" "${PCT_OPTS[@]}" >/dev/null 2>&1
[[ -n "${SSH_KEY_FILE:-}" ]] && rm -f "$SSH_KEY_FILE"
msg_ok "Container ${CT_ID} created"

# Step 3: Start
msg_info "Starting container"
pct start "$CT_ID"
sleep 3
msg_ok "Started"

# Step 4: Wait for network
msg_info "Waiting for network"
for i in $(seq 1 30); do
    pct exec "$CT_ID" -- ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && break
    sleep 1
done
msg_ok "Network ready"

# Step 5: Install Docker
msg_info "Installing Docker (1-2 min)"
pct exec "$CT_ID" -- bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq ca-certificates curl gnupg git >/dev/null 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
' >/dev/null 2>&1
msg_ok "Docker installed"

# Step 6: SSH setup
if $ENABLE_SSH; then
    msg_info "Enabling SSH service"
    pct exec "$CT_ID" -- bash -c '
        apt-get install -y -qq openssh-server >/dev/null 2>&1
        sed -i "s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
        systemctl enable ssh >/dev/null 2>&1
        systemctl start ssh
    ' >/dev/null 2>&1
    if [[ -n "$CT_SSH_KEY" ]]; then
        pct exec "$CT_ID" -- bash -c "
            mkdir -p /root/.ssh && chmod 700 /root/.ssh
            echo '${CT_SSH_KEY}' >> /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys
        " >/dev/null 2>&1
    fi
    msg_ok "SSH enabled"
fi

# Step 7: Deploy NetBoot Catalog
msg_info "Deploying ${APP} (building Docker image — may take 2-5 min)"
pct exec "$CT_ID" -- bash -c "
    git clone ${APP_REPO} /opt/netboot-catalog 2>&1 | tail -1
    cd /opt/netboot-catalog
    echo '  Building Docker image...'
    docker compose build 2>&1 | grep -E '(Step|Successfully|DONE)' || true
    mkdir -p /srv/import /srv/catalog
    docker compose up -d 2>&1 | tail -2
"
msg_ok "${APP} deployed"

# Step 7: Get IP
sleep 3
CT_IP=$(pct exec "$CT_ID" -- bash -c "ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}'" 2>/dev/null || echo "unknown")

# === Complete ===
echo ""
echo -e "${GN}════════════════════════════════════════════════${NC}"
echo -e "${GN}  ${APP} — Installation Complete${NC}"
echo -e "${GN}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Container:     ${GN}${CT_ID}${NC} (${CT_HOSTNAME})"
echo -e "  IP Address:    ${GN}${CT_IP}${NC}"
if $GENERATED_PW; then
    echo -e "  Root Password: ${YW}${CT_PASSWORD}${NC} (auto-generated)"
fi
if $ENABLE_SSH; then
    echo -e "  SSH:           ${GN}ssh root@${CT_IP}${NC}"
fi
echo ""
echo -e "  ${BL}Health:${NC}  curl http://${CT_IP}/health"
echo -e "  ${BL}Menu:${NC}    curl http://${CT_IP}/tftp/menu.ipxe"
echo ""
echo -e "  ${YW}Import:${NC}  pct push ${CT_ID} <local.iso> /srv/import/<file>.iso"
echo -e "  ${YW}List:${NC}    pct exec ${CT_ID} -- docker exec nbc nbc list"
echo -e "  ${YW}Logs:${NC}    pct exec ${CT_ID} -- docker logs nbc"
echo ""
echo -e "  Drop ISOs into ${YW}/srv/import/${NC} for auto-import (10s polling)."
echo ""
