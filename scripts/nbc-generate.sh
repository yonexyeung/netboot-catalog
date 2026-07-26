#!/usr/bin/env bash
# nbc-generate.sh — Generate iPXE boot menu from catalog entries
# Usage: nbc-generate.sh [--output <file>] [--base-url <url>]
#
# Reads all entries in catalog/ and produces an iPXE menu script.

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CATALOG_DIR="${CATALOG_DIR:-$PROJECT_ROOT/catalog}"
TEMPLATES_DIR="${TEMPLATES_DIR:-$PROJECT_ROOT/templates}"
OUTPUT_FILE=""
BASE_URL="${NBC_BASE_URL:-http://\${next-server}/catalog}"

# --- Helpers ---
log() { echo "[nbc] $*"; }
err() { echo "[nbc] ERROR: $*" >&2; }
die() { err "$*"; exit 1; }

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --base-url|-b)
            BASE_URL="$2"
            shift 2
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

# Check dependencies
command -v yq >/dev/null || die "Missing dependency: yq"

# --- Generate menu ---
generate_menu() {
    local entries=()
    
    # Collect all catalog entries
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
        local entry_dir id name
        entry_dir=$(dirname "$recipe")
        id=$(yq '.id' "$recipe")
        name=$(yq '.name' "$recipe")
        
        echo "item ${id} ${name}"
        
        # Add variants
        if [[ $(yq '.boot.variants // "" | length' "$recipe" 2>/dev/null) -gt 0 ]]; then
            local variant_keys
            variant_keys=$(yq '.boot.variants | keys | .[]' "$recipe" 2>/dev/null || true)
            for vkey in $variant_keys; do
                echo "item ${id}--${vkey} ${name} (${vkey})"
            done
        fi
    done
    
    # Exit item + choose
    cat <<'EOF'
item --gap --
item exit Exit to local boot
choose --timeout ${menu-timeout} --default ${menu-default} selected || goto exit
goto ${selected}
EOF

    # Boot entries
    for recipe in "${entries[@]}"; do
        local entry_dir id kernel_file initrd_file rootfs_file boot_args
        entry_dir=$(dirname "$recipe")
        id=$(yq '.id' "$recipe")
        kernel_file=$(yq '.assets.kernel' "$recipe")
        initrd_file=$(yq '.assets.initrd' "$recipe")
        rootfs_file=$(yq '.assets.rootfs' "$recipe")
        boot_args=$(yq '.boot.default' "$recipe")
        
        local entry_url="${BASE_URL}/${id}"
        
        # Expand template variables in boot args
        local expanded_args="$boot_args"
        expanded_args="${expanded_args//\{\{base_url\}\}/$entry_url}"
        expanded_args="${expanded_args//\{\{kernel_url\}\}/$entry_url/$kernel_file}"
        expanded_args="${expanded_args//\{\{initrd_url\}\}/$entry_url/$initrd_file}"
        expanded_args="${expanded_args//\{\{rootfs_url\}\}/$entry_url/$rootfs_file}"
        
        echo ""
        echo ":${id}"
        echo "kernel ${entry_url}/${kernel_file} ${expanded_args}"
        echo "initrd ${entry_url}/${initrd_file}"
        echo "boot"
        
        # Variants
        if [[ $(yq '.boot.variants // "" | length' "$recipe" 2>/dev/null) -gt 0 ]]; then
            local variant_keys
            variant_keys=$(yq '.boot.variants | keys | .[]' "$recipe" 2>/dev/null || true)
            for vkey in $variant_keys; do
                local vargs
                vargs=$(yq ".boot.variants.${vkey}" "$recipe")
                
                local expanded_vargs="$vargs"
                expanded_vargs="${expanded_vargs//\{\{base_url\}\}/$entry_url}"
                expanded_vargs="${expanded_vargs//\{\{kernel_url\}\}/$entry_url/$kernel_file}"
                expanded_vargs="${expanded_vargs//\{\{initrd_url\}\}/$entry_url/$initrd_file}"
                expanded_vargs="${expanded_vargs//\{\{rootfs_url\}\}/$entry_url/$rootfs_file}"
                
                echo ""
                echo ":${id}--${vkey}"
                echo "kernel ${entry_url}/${kernel_file} ${expanded_vargs}"
                echo "initrd ${entry_url}/${initrd_file}"
                echo "boot"
            done
        fi
    done
    
    # Exit label
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
