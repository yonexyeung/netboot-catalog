#!/usr/bin/env bash
# nbc-generate.sh — Generate iPXE boot menu from catalog entries
# Usage: nbc-generate.sh [--output <file>] [--base-url <url>]
#
# Reads all entries in catalog/ and produces an iPXE menu script.
# Boot args are read from adapter YAML (source of truth), not recipe.yaml.

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CATALOG_DIR="${CATALOG_DIR:-$PROJECT_ROOT/catalog}"
ADAPTERS_DIR="${ADAPTERS_DIR:-$PROJECT_ROOT/adapters}"
OUTPUT_FILE=""
BASE_URL="${NBC_BASE_URL:-http://\${next-server}/catalog}"

# --- Helpers ---
log() { echo "[nbc] $*"; }
err() { echo "[nbc] ERROR: $*" >&2; }
die() { err "$*"; exit 1; }

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT_FILE="$2"; shift 2 ;;
        --base-url|-b) BASE_URL="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

command -v yq >/dev/null || die "Missing dependency: yq"

# --- Resolve adapter file from recipe ---
get_adapter_file() {
    local recipe="$1"
    local adapter_name
    adapter_name=$(yq '.adapter' "$recipe")
    local adapter_file="$ADAPTERS_DIR/${adapter_name}.yaml"
    if [[ -f "$adapter_file" ]]; then
        echo "$adapter_file"
    else
        echo ""
    fi
}

# --- Generate menu ---
generate_menu() {
    local entries=()

    for recipe in "$CATALOG_DIR"/*/recipe.yaml; do
        [[ -f "$recipe" ]] || continue
        entries+=("$recipe")
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        die "No catalog entries found in $CATALOG_DIR"
    fi

    # Header
    cat <<'EOF'
#!ipxe
# NetBoot Catalog — Auto-generated iPXE Menu
# Do not edit manually — run `nbc generate` to regenerate.

set menu-timeout 30000
set menu-default exit

:start
menu NetBoot Catalog
EOF

    # Menu items
    for recipe in "${entries[@]}"; do
        local id name adapter_file
        id=$(yq '.id' "$recipe")
        name=$(yq '.name' "$recipe")
        adapter_file=$(get_adapter_file "$recipe")

        echo "item ${id} ${name}"

        # Variants from adapter YAML (source of truth)
        if [[ -n "$adapter_file" ]] && yq -e '.boot.variants' "$adapter_file" >/dev/null 2>&1; then
            local variant_keys
            variant_keys=$(yq '.boot.variants | keys | .[]' "$adapter_file" 2>/dev/null || true)
            for vkey in $variant_keys; do
                echo "item ${id}--${vkey} ${name} (${vkey})"
            done
        fi
    done

    # Exit + choose
    cat <<'EOF'
item --gap --
item exit Exit to local boot
choose --timeout ${menu-timeout} --default ${menu-default} selected || goto exit
goto ${selected}
EOF

    # Extract server host from BASE_URL for TFTP
    local server_host
    server_host=$(echo "$BASE_URL" | sed 's|https\?://||; s|/.*||')

    # Boot entries
    for recipe in "${entries[@]}"; do
        local id kernel_file initrd_file rootfs_file iso_filename adapter_file boot_args
        id=$(yq '.id' "$recipe")
        kernel_file=$(yq '.assets.kernel' "$recipe")
        initrd_file=$(yq '.assets.initrd' "$recipe")
        rootfs_file=$(yq '.assets.rootfs // ""' "$recipe" 2>/dev/null || echo "")
        iso_filename=$(yq '.iso_filename // ""' "$recipe" 2>/dev/null || echo "")
        adapter_file=$(get_adapter_file "$recipe")

        # Boot args from ADAPTER (not recipe) — adapter is source of truth
        if [[ -n "$adapter_file" ]]; then
            boot_args=$(yq '.boot.default' "$adapter_file")
        else
            # Fallback to recipe if adapter not found
            boot_args=$(yq '.boot.default' "$recipe" 2>/dev/null || echo "")
        fi

        local entry_url="${BASE_URL}/${id}"
        local tftp_prefix="catalog/${id}"

        # Expand template variables
        local expanded_args="$boot_args"
        expanded_args="${expanded_args//\{\{base_url\}\}/$entry_url}"
        expanded_args="${expanded_args//\{\{kernel_url\}\}/$entry_url/$kernel_file}"
        expanded_args="${expanded_args//\{\{initrd_url\}\}/$entry_url/$initrd_file}"
        expanded_args="${expanded_args//\{\{rootfs_url\}\}/$entry_url/$rootfs_file}"
        expanded_args="${expanded_args//\{\{iso_filename\}\}/$iso_filename}"

        echo ""
        echo ":${id}"
        echo "kernel tftp://${server_host}/${tftp_prefix}/${kernel_file} ${expanded_args}"
        echo "initrd tftp://${server_host}/${tftp_prefix}/${initrd_file}"
        echo "boot"

        # Variants from adapter YAML
        if [[ -n "$adapter_file" ]] && yq -e '.boot.variants' "$adapter_file" >/dev/null 2>&1; then
            local variant_keys
            variant_keys=$(yq '.boot.variants | keys | .[]' "$adapter_file" 2>/dev/null || true)
            for vkey in $variant_keys; do
                local vargs
                vargs=$(yq ".boot.variants.${vkey}" "$adapter_file")

                local expanded_vargs="$vargs"
                expanded_vargs="${expanded_vargs//\{\{base_url\}\}/$entry_url}"
                expanded_vargs="${expanded_vargs//\{\{kernel_url\}\}/$entry_url/$kernel_file}"
                expanded_vargs="${expanded_vargs//\{\{initrd_url\}\}/$entry_url/$initrd_file}"
                expanded_vargs="${expanded_vargs//\{\{rootfs_url\}\}/$entry_url/$rootfs_file}"
                expanded_vargs="${expanded_vargs//\{\{iso_filename\}\}/$iso_filename}"

                echo ""
                echo ":${id}--${vkey}"
                echo "kernel tftp://${server_host}/${tftp_prefix}/${kernel_file} ${expanded_vargs}"
                echo "initrd tftp://${server_host}/${tftp_prefix}/${initrd_file}"
                echo "boot"
            done
        fi
    done

    echo ""
    echo ":exit"
    echo "exit"
}

# --- Main ---
if [[ -n "$OUTPUT_FILE" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    generate_menu > "$OUTPUT_FILE"
    log "Generated iPXE menu: $OUTPUT_FILE ($(grep -c '^:' "$OUTPUT_FILE") entries)"
else
    generate_menu
fi
