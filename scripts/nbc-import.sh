#!/usr/bin/env bash
# nbc-import.sh — Import an ISO into NetBoot Catalog
# Usage: nbc-import.sh <iso-file>
#
# Workflow: mount ISO → detect adapter → extract assets → generate recipe

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ADAPTERS_DIR="${ADAPTERS_DIR:-$PROJECT_ROOT/adapters}"
CATALOG_DIR="${CATALOG_DIR:-$PROJECT_ROOT/catalog}"

# --- Helpers ---
log() { echo "[nbc] $*"; }
err() { echo "[nbc] ERROR: $*" >&2; }
die() { err "$*"; exit 1; }

# Check dependencies
check_deps() {
    local missing=()
    for cmd in cp sha256sum; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    # yq is needed to parse YAML adapters
    if ! command -v yq >/dev/null; then
        missing+=("yq")
    fi
    # Need at least one extraction method
    if ! command -v mount >/dev/null && ! command -v bsdtar >/dev/null && ! command -v 7z >/dev/null; then
        missing+=("mount or bsdtar or 7z")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing dependencies: ${missing[*]}"
    fi
}

# Mount or extract ISO to temp directory
# Tries: mount → bsdtar → 7z (in order of preference)
mount_iso() {
    local iso="$1"
    local mount_point
    local tmp_base="${NBC_TMP_DIR:-/var/tmp}"
    mount_point=$(mktemp -d "$tmp_base/nbc-mount.XXXXXX")
    
    # Method 1: mount -o loop (requires root + loop device support)
    if command -v mount >/dev/null && mount -o loop,ro "$iso" "$mount_point" 2>/dev/null; then
        echo "mount:$mount_point"
        return 0
    fi
    
    # Method 2: bsdtar (no privileges needed)
    if command -v bsdtar >/dev/null; then
        log "  mount failed, falling back to bsdtar..."
        if bsdtar -xf "$iso" -C "$mount_point" 2>/dev/null; then
            echo "extract:$mount_point"
            return 0
        fi
    fi
    
    # Method 3: 7z (no privileges needed)
    if command -v 7z >/dev/null; then
        log "  mount/bsdtar failed, falling back to 7z..."
        if 7z x -o"$mount_point" "$iso" >/dev/null 2>&1; then
            echo "extract:$mount_point"
            return 0
        fi
    fi
    
    rmdir "$mount_point" 2>/dev/null || rm -rf "$mount_point"
    die "Failed to mount/extract ISO: $iso (tried: mount, bsdtar, 7z)"
}

# Unmount and cleanup
unmount_iso() {
    local mount_info="$1"
    local method="${mount_info%%:*}"
    local path="${mount_info#*:}"
    
    if [[ "$method" == "mount" ]]; then
        umount "$path" 2>/dev/null || true
        rmdir "$path" 2>/dev/null || true
    else
        # Extracted — just remove
        rm -rf "$path"
    fi
}

# Run detection rules from an adapter YAML against a mount point
# Returns 0 if all rules match, 1 otherwise
detect_adapter() {
    local adapter_file="$1"
    local mount_point="$2"
    
    local rule_count
    rule_count=$(yq '.detection | length' "$adapter_file")
    
    for ((i=0; i<rule_count; i++)); do
        local rule_keys
        rule_keys=$(yq ".detection[$i] | keys | .[]" "$adapter_file")
        
        for key in $rule_keys; do
            case "$key" in
                file_exists)
                    local path
                    path=$(yq ".detection[$i].file_exists" "$adapter_file")
                    if [[ ! -e "$mount_point/$path" ]]; then
                        return 1
                    fi
                    ;;
                file_contains)
                    local fc_path fc_pattern
                    fc_path=$(yq ".detection[$i].file_contains.path" "$adapter_file")
                    fc_pattern=$(yq ".detection[$i].file_contains.pattern" "$adapter_file")
                    if [[ ! -f "$mount_point/$fc_path" ]]; then
                        return 1
                    fi
                    if ! grep -qE "$fc_pattern" "$mount_point/$fc_path" 2>/dev/null; then
                        return 1
                    fi
                    ;;
                volume_label)
                    # TODO: implement volume label check
                    ;;
            esac
        done
    done
    
    return 0
}

# Find matching adapter for mounted ISO
find_adapter() {
    local mount_point="$1"
    
    for adapter_file in "$ADAPTERS_DIR"/*.yaml; do
        [[ -f "$adapter_file" ]] || continue
        if detect_adapter "$adapter_file" "$mount_point"; then
            echo "$adapter_file"
            return 0
        fi
    done
    
    return 1
}

# Extract assets from mounted ISO using adapter definition
extract_assets() {
    local adapter_file="$1"
    local mount_point="$2"
    local dest_dir="$3"
    
    mkdir -p "$dest_dir"
    
    local kernel initrd rootfs
    kernel=$(yq '.assets.kernel' "$adapter_file")
    initrd=$(yq '.assets.initrd' "$adapter_file")
    rootfs=$(yq '.assets.rootfs' "$adapter_file")
    
    # Validate source files exist
    [[ -f "$mount_point/$kernel" ]] || die "Kernel not found: $kernel"
    [[ -f "$mount_point/$initrd" ]] || die "Initrd not found: $initrd"
    
    # Check if rootfs is optional
    local rootfs_optional
    rootfs_optional=$(yq '.assets.rootfs_optional // "false"' "$adapter_file")
    
    if [[ -f "$mount_point/$rootfs" ]]; then
        : # rootfs exists, will copy below
    elif [[ "$rootfs_optional" == "true" ]]; then
        log "  Rootfs not found (optional): $rootfs"
        rootfs=""
    else
        die "Rootfs not found: $rootfs"
    fi
    
    # Copy assets (use basename to flatten into dest dir)
    log "  Extracting kernel: $kernel"
    cp "$mount_point/$kernel" "$dest_dir/$(basename "$kernel")"
    
    log "  Extracting initrd: $initrd"
    cp "$mount_point/$initrd" "$dest_dir/$(basename "$initrd")"
    
    if [[ -n "$rootfs" ]]; then
        log "  Extracting rootfs: $rootfs"
        cp "$mount_point/$rootfs" "$dest_dir/$(basename "$rootfs")"
    fi
}

# Generate recipe.yaml for the catalog entry
generate_recipe() {
    local adapter_file="$1"
    local dest_dir="$2"
    local iso_file="$3"
    
    local id name distribution rootfs_type boot_default
    id=$(yq '.id' "$adapter_file")
    name=$(yq '.name' "$adapter_file")
    distribution=$(yq '.distribution' "$adapter_file")
    rootfs_type=$(yq '.assets.rootfs_type' "$adapter_file")
    boot_default=$(yq '.boot.default' "$adapter_file")
    
    local kernel_file initrd_file rootfs_file
    kernel_file=$(basename "$(yq '.assets.kernel' "$adapter_file")")
    initrd_file=$(basename "$(yq '.assets.initrd' "$adapter_file")")
    rootfs_file=$(yq '.assets.rootfs' "$adapter_file")
    
    # rootfs may not have been extracted (optional)
    if [[ -f "$dest_dir/$(basename "$rootfs_file")" ]]; then
        rootfs_file=$(basename "$rootfs_file")
    else
        rootfs_file=""
    fi
    
    # Get ISO hash for provenance
    local iso_sha256
    iso_sha256=$(sha256sum "$iso_file" | awk '{print $1}')
    
    # Get variants
    local variants_yaml=""
    if [[ $(yq '.boot.variants // empty' "$adapter_file") != "" ]]; then
        variants_yaml=$(yq '.boot.variants' "$adapter_file")
    fi
    
    # Write recipe
    cat > "$dest_dir/recipe.yaml" <<EOF
# Auto-generated by nbc-import
# Do not edit manually — re-import ISO to regenerate

schema_version: "1"
id: ${id}
name: "${name}"
distribution: ${distribution}
imported_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
source_iso: "$(basename "$iso_file")"
source_iso_sha256: ${iso_sha256}
adapter: $(basename "$adapter_file" .yaml)

assets:
  kernel: ${kernel_file}
  initrd: ${initrd_file}
  rootfs: ${rootfs_file}
  rootfs_type: ${rootfs_type}

boot:
  default: "${boot_default}"
EOF

    if [[ -n "$variants_yaml" ]]; then
        echo "  variants:" >> "$dest_dir/recipe.yaml"
        yq '.boot.variants | to_entries | .[] | "    " + .key + ": \"" + .value + "\""' "$adapter_file" >> "$dest_dir/recipe.yaml"
    fi
    
    log "  Generated recipe.yaml"
}

# Validate extracted entry
validate_entry() {
    local adapter_file="$1"
    local dest_dir="$2"
    
    local rule_count
    rule_count=$(yq '.validation.required_files | length' "$adapter_file")
    
    for ((i=0; i<rule_count; i++)); do
        local required
        required=$(yq ".validation.required_files[$i]" "$adapter_file")
        if [[ ! -f "$dest_dir/$required" ]]; then
            err "Validation failed: missing $required"
            return 1
        fi
    done
    
    log "  Validation passed"
    return 0
}

# --- Main ---
main() {
    local iso_file="${1:-}"
    
    if [[ -z "$iso_file" ]]; then
        echo "Usage: nbc-import.sh <iso-file>"
        echo ""
        echo "Import a Linux ISO into the NetBoot Catalog."
        exit 1
    fi
    
    [[ -f "$iso_file" ]] || die "File not found: $iso_file"
    
    check_deps
    
    log "Importing: $iso_file"
    
    # Step 1: Mount
    log "Mounting ISO..."
    local mount_info
    mount_info=$(mount_iso "$iso_file")
    local mount_point="${mount_info#*:}"
    trap "unmount_iso '$mount_info'" EXIT
    
    # Step 2: Detect
    log "Detecting distribution..."
    local adapter_file
    if ! adapter_file=$(find_adapter "$mount_point"); then
        die "No matching adapter found for this ISO"
    fi
    log "  Matched: $(yq '.name' "$adapter_file")"
    
    # Step 3: Determine entry directory
    local adapter_id
    adapter_id=$(yq '.id' "$adapter_file")
    local entry_dir="$CATALOG_DIR/$adapter_id"
    
    if [[ -d "$entry_dir" ]]; then
        log "  Entry already exists, overwriting: $entry_dir"
        rm -rf "$entry_dir"
    fi
    
    # Step 4: Extract to temp, then atomic move
    local temp_dir
    temp_dir=$(mktemp -d "${NBC_TMP_DIR:-/var/tmp}/nbc-extract.XXXXXX")
    
    log "Extracting assets..."
    extract_assets "$adapter_file" "$mount_point" "$temp_dir"
    
    # Step 5: Generate recipe
    log "Generating recipe..."
    generate_recipe "$adapter_file" "$temp_dir" "$iso_file"
    
    # Step 6: Validate
    log "Validating..."
    if ! validate_entry "$adapter_file" "$temp_dir"; then
        rm -rf "$temp_dir"
        die "Validation failed — entry not created"
    fi
    
    # Step 7: Atomic move to catalog
    mkdir -p "$CATALOG_DIR"
    mv "$temp_dir" "$entry_dir"
    
    log "Done! Entry created: $entry_dir"
    log ""
    log "  Adapter:  $(basename "$adapter_file" .yaml)"
    log "  Kernel:   $(yq '.assets.kernel' "$entry_dir/recipe.yaml")"
    log "  Initrd:   $(yq '.assets.initrd' "$entry_dir/recipe.yaml")"
    log "  Rootfs:   $(yq '.assets.rootfs' "$entry_dir/recipe.yaml")"
}

main "$@"
