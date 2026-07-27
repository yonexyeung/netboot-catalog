#!/usr/bin/env bash
# pve-install.sh — Proxmox VE Helper Script for NetBoot Catalog
#
# Creates a Debian 13 LXC with Docker and deploys netboot-catalog.
# Features whiptail GUI with auto-detection of host storage, bridges, and VLANs.
#
# Run on Proxmox VE host:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/yonexyeung/netboot-catalog/main/scripts/pve-install.sh)"

set -euo pipefail

APP="NetBoot Catalog"
APP_REPO="https://github.com/yonexyeung/netboot-catalog.git"
STEPS_TOTAL=9

# --- Pre-flight ---
[[ $EUID -eq 0 ]] || { echo "ERROR: Must run as root."; exit 1; }
[[ -d /etc/pve ]] || { echo "ERROR: This script must be run on a Proxmox VE host."; exit 1; }
command -v pct >/dev/null || { echo "ERROR: pct not found."; exit 1; }
command -v whiptail >/dev/null || apt-get install -y -qq whiptail >/dev/null 2>&1

# --- Colors ---
GN='\033[0;32m'; YW='\033[0;33m'; RD='\033[0;31m'; BL='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'
BFR='\r\033[K'; CM="${GN}✓${NC}"; HOLD="${YW}⏳${NC}"

msg_info() { echo -ne "${HOLD} ${YW}${1}${NC}"; }
msg_ok()   { echo -e "${BFR}${CM} ${GN}${1}${NC}"; }
msg_err()  { echo -e "${BFR}${RD}✗ ${1}${NC}"; exit 1; }

# --- Whiptail helpers ---
DIALOG_W=62
DIALOG_H=18

step_title() {
    echo "$APP — Step $1/$STEPS_TOTAL: $2"
}

# Validate numeric input
is_numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }

# Validate CIDR notation
is_cidr() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; }

# --- Storage detection ---
get_rootdir_storages() {
    local stores=()
    local current_store="" is_active=true
    while IFS= read -r line; do
        if [[ "$line" =~ ^[a-z]+:\ (.+)$ ]]; then
            current_store="${BASH_REMATCH[1]}"; is_active=true
        elif [[ "$line" =~ ^[[:space:]]+disable$ ]]; then
            is_active=false
        elif [[ "$line" =~ ^[[:space:]]+content[[:space:]]+(.+)$ ]] && $is_active; then
            echo "${BASH_REMATCH[1]}" | grep -qE "(rootdir|images)" && stores+=("$current_store")
        fi
    done < /etc/pve/storage.cfg
    echo "${stores[@]}"
}

get_vztmpl_storages() {
    local stores=()
    local current_store="" is_active=true
    while IFS= read -r line; do
        if [[ "$line" =~ ^[a-z]+:\ (.+)$ ]]; then
            current_store="${BASH_REMATCH[1]}"; is_active=true
        elif [[ "$line" =~ ^[[:space:]]+disable$ ]]; then
            is_active=false
        elif [[ "$line" =~ ^[[:space:]]+content[[:space:]]+(.+)$ ]] && $is_active; then
            echo "${BASH_REMATCH[1]}" | grep -q "vztmpl" && stores+=("$current_store")
        fi
    done < /etc/pve/storage.cfg
    echo "${stores[@]}"
}

get_bridges() {
    ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | sort
}

whiptail_select() {
    local title="$1" prompt="$2"; shift 2
    local items=("$@") menu_args=() first=true
    for item in "${items[@]}"; do
        if $first; then menu_args+=("$item" "" "ON"); first=false
        else menu_args+=("$item" "" "OFF"); fi
    done
    whiptail --title "$title" --radiolist \
        "$prompt\n\nUse SPACE to select, ENTER to confirm." \
        $DIALOG_H $DIALOG_W 6 "${menu_args[@]}" 3>&1 1>&2 2>&3
}

# === MAIN ===

# Welcome
whiptail --title "$APP" --msgbox \
"  ┌─────────────────────────────────────┐
  │   Drop ISO. Network Boot.           │
  │   Open Source.                       │
  └─────────────────────────────────────┘

  This installer will:

    1. Create a Debian 13 LXC container
    2. Install Docker
    3. Deploy NetBoot Catalog
    4. Start the PXE boot service

  ⓘ Your existing DHCP server will NOT
    be replaced (ProxyDHCP mode)." $DIALOG_H $DIALOG_W

# --- Step 1: Container ID ---
NEXTID=$(pvesh get /cluster/nextid)
while true; do
    CT_ID=$(whiptail --title "$(step_title 1 "Container ID")" \
        --inputbox "Enter container ID:" 10 $DIALOG_W "$NEXTID" 3>&1 1>&2 2>&3) || exit 0
    is_numeric "$CT_ID" && break
    whiptail --title "Invalid Input" --msgbox "Container ID must be a number." 8 $DIALOG_W
done

# --- Step 2: Hostname ---
CT_HOSTNAME=$(whiptail --title "$(step_title 2 "Hostname")" \
    --inputbox "Enter hostname:" 10 $DIALOG_W "netboot-catalog" 3>&1 1>&2 2>&3) || exit 0
[[ -z "$CT_HOSTNAME" ]] && CT_HOSTNAME="netboot-catalog"

# --- Step 3: Storage ---
ROOTFS_STORES=($(get_rootdir_storages))
[[ ${#ROOTFS_STORES[@]} -eq 0 ]] && msg_err "No active storage supports rootdir/images."
if [[ ${#ROOTFS_STORES[@]} -eq 1 ]]; then
    CT_STORAGE="${ROOTFS_STORES[0]}"
else
    CT_STORAGE=$(whiptail_select "$(step_title 3 "Storage")" \
        "Select storage for container root disk:" "${ROOTFS_STORES[@]}") || exit 0
fi

TPL_STORES=($(get_vztmpl_storages))
[[ ${#TPL_STORES[@]} -eq 0 ]] && msg_err "No active storage supports vztmpl."
if [[ ${#TPL_STORES[@]} -eq 1 ]]; then
    CT_TPL_STORAGE="${TPL_STORES[0]}"
else
    CT_TPL_STORAGE=$(whiptail_select "$(step_title 3 "Template Storage")" \
        "Select storage for CT templates:" "${TPL_STORES[@]}") || exit 0
fi

# --- Step 4: Resources ---
while true; do
    CT_DISK=$(whiptail --title "$(step_title 4 "Resources — Disk")" \
        --inputbox "Root disk size (GB):\n\n  ⓘ Minimum 20GB recommended for ISO storage" \
        12 $DIALOG_W "20" 3>&1 1>&2 2>&3) || exit 0
    is_numeric "$CT_DISK" && [[ $CT_DISK -ge 8 ]] && break
    whiptail --title "Invalid Input" --msgbox "Disk size must be a number (minimum 8)." 8 $DIALOG_W
done

while true; do
    CT_RAM=$(whiptail --title "$(step_title 4 "Resources — Memory")" \
        --inputbox "RAM (MB):" 10 $DIALOG_W "2048" 3>&1 1>&2 2>&3) || exit 0
    is_numeric "$CT_RAM" && [[ $CT_RAM -ge 512 ]] && break
    whiptail --title "Invalid Input" --msgbox "RAM must be a number (minimum 512)." 8 $DIALOG_W
done

while true; do
    CT_CPU=$(whiptail --title "$(step_title 4 "Resources — CPU")" \
        --inputbox "CPU cores:" 10 $DIALOG_W "2" 3>&1 1>&2 2>&3) || exit 0
    is_numeric "$CT_CPU" && [[ $CT_CPU -ge 1 ]] && break
    whiptail --title "Invalid Input" --msgbox "CPU must be a number (minimum 1)." 8 $DIALOG_W
done

# --- Step 5: Network ---
BRIDGES=($(get_bridges))
[[ ${#BRIDGES[@]} -eq 0 ]] && BRIDGES=("vmbr0")
if [[ ${#BRIDGES[@]} -eq 1 ]]; then
    CT_BRIDGE="${BRIDGES[0]}"
else
    CT_BRIDGE=$(whiptail_select "$(step_title 5 "Network — Bridge")" \
        "Select bridge for PXE traffic:" "${BRIDGES[@]}") || exit 0
fi

CT_VLAN=$(whiptail --title "$(step_title 5 "Network — VLAN")" \
    --inputbox "VLAN tag (leave empty for none):" 10 $DIALOG_W "" 3>&1 1>&2 2>&3) || CT_VLAN=""

# --- Step 6: IP ---
if whiptail --title "$(step_title 6 "IP Address")" \
    --yesno "Use DHCP for container IP?\n\nSelect <No> for static IP configuration." 10 $DIALOG_W; then
    CT_NET_IP="ip=dhcp"
else
    while true; do
        STATIC_IP=$(whiptail --title "$(step_title 6 "Static IP")" \
            --inputbox "IP address (CIDR format):\n\n  Example: 192.168.50.200/24" \
            12 $DIALOG_W "" 3>&1 1>&2 2>&3) || exit 0
        is_cidr "$STATIC_IP" && break
        whiptail --title "Invalid Input" --msgbox "Enter a valid CIDR address (e.g. 192.168.50.200/24)." 8 $DIALOG_W
    done
    STATIC_GW=$(whiptail --title "$(step_title 6 "Gateway")" \
        --inputbox "Gateway IP:" 10 $DIALOG_W "" 3>&1 1>&2 2>&3) || exit 0
    CT_NET_IP="ip=${STATIC_IP},gw=${STATIC_GW}"
fi

# --- Step 7: Authentication ---
CT_PASSWORD=""
GENERATED_PW=false
while true; do
    CT_PASSWORD=$(whiptail --title "$(step_title 7 "Authentication — Password")" \
        --passwordbox "Set root password (leave empty to auto-generate):" \
        10 $DIALOG_W 3>&1 1>&2 2>&3) || exit 0
    if [[ -z "$CT_PASSWORD" ]]; then
        CT_PASSWORD=$(openssl rand -base64 12)
        GENERATED_PW=true
        break
    fi
    # Confirm password
    PW_CONFIRM=$(whiptail --title "$(step_title 7 "Confirm Password")" \
        --passwordbox "Confirm password:" 10 $DIALOG_W 3>&1 1>&2 2>&3) || exit 0
    if [[ "$CT_PASSWORD" == "$PW_CONFIRM" ]]; then break; fi
    whiptail --title "Mismatch" --msgbox "Passwords do not match. Try again." 8 $DIALOG_W
done

CT_SSH_KEY=""
if whiptail --title "$(step_title 7 "Authentication — SSH Key")" \
    --yesno "Add SSH public key for passwordless login?" 10 $DIALOG_W; then
    CT_SSH_KEY=$(whiptail --title "$(step_title 7 "SSH Key")" \
        --inputbox "Paste public key (ssh-ed25519 ... or ssh-rsa ...):" \
        12 76 "" 3>&1 1>&2 2>&3) || CT_SSH_KEY=""
fi

# --- Step 8: SSH Service ---
ENABLE_SSH=false
if whiptail --title "$(step_title 8 "SSH Service")" \
    --yesno "Enable SSH service?\n\nAllows remote access via: ssh root@<container-ip>" 10 $DIALOG_W; then
    ENABLE_SSH=true
fi

# --- Step 9: Confirm ---
NET_STR="name=eth0,bridge=${CT_BRIDGE}"
[[ -n "$CT_VLAN" ]] && NET_STR="${NET_STR},tag=${CT_VLAN}"
NET_STR="${NET_STR},${CT_NET_IP}"

CONFIRM_TEXT="
  Container ID:    ${CT_ID}
  Hostname:        ${CT_HOSTNAME}

  Storage:         ${CT_STORAGE}
  Templates:       ${CT_TPL_STORAGE}
  Disk:            ${CT_DISK} GB
  RAM:             ${CT_RAM} MB
  CPU:             ${CT_CPU} cores

  Bridge:          ${CT_BRIDGE}
  VLAN:            ${CT_VLAN:-none}
  IP:              ${CT_NET_IP}
  SSH:             $(if $ENABLE_SSH; then echo "enabled"; else echo "disabled"; fi)

  Create and install ${APP}?"

whiptail --title "$(step_title 9 "Confirm")" --yesno "$CONFIRM_TEXT" 22 $DIALOG_W || exit 0

# === Installation ===
echo ""
echo -e "${BL}Installing ${APP}...${NC}"
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
msg_info "Creating container ${CT_ID}"
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
msg_ok "Container started"

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

# Step 6: SSH
if $ENABLE_SSH; then
    msg_info "Enabling SSH"
    pct exec "$CT_ID" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
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

# Step 7: Deploy
msg_info "Deploying ${APP} (2-5 min)"
pct exec "$CT_ID" -- bash -c "
    git clone --quiet ${APP_REPO} /opt/netboot-catalog
    cd /opt/netboot-catalog
    docker compose build --quiet
    mkdir -p /srv/import /srv/catalog
    docker compose up -d --quiet-pull
" >/dev/null 2>&1
msg_ok "${APP} deployed"

# Get IP
sleep 3
CT_IP=$(pct exec "$CT_ID" -- bash -c "ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}'" 2>/dev/null || echo "unknown")

# === Complete ===
echo ""
echo -e "${GN}┌──────────────────────────────────────────────┐${NC}"
echo -e "${GN}│  ${APP} — Installation Complete       │${NC}"
echo -e "${GN}└──────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  Container     ${GN}${CT_ID}${NC} (${CT_HOSTNAME})"
echo -e "  IP Address    ${GN}${CT_IP}${NC}"
if $GENERATED_PW; then
echo -e "  Password      ${YW}${CT_PASSWORD}${NC} ${DIM}(auto-generated)${NC}"
fi
if $ENABLE_SSH; then
echo -e "  SSH           ${GN}ssh root@${CT_IP}${NC}"
fi
echo ""
echo -e "  ${DIM}─── Services ───────────────────────────────${NC}"
echo -e "  Health        curl http://${CT_IP}/health"
echo -e "  Boot Menu     http://${CT_IP}/tftp/menu.ipxe"
echo ""
echo -e "  ${DIM}─── Usage ──────────────────────────────────${NC}"
echo -e "  Import ISO    pct push ${CT_ID} <file>.iso /srv/import/<file>.iso"
echo -e "  List          pct exec ${CT_ID} -- docker exec nbc nbc list"
echo -e "  Logs          pct exec ${CT_ID} -- docker logs nbc"
echo ""
echo -e "  ${DIM}ISOs dropped into /srv/import/ are auto-imported (10s polling).${NC}"
echo ""
