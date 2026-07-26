#!/usr/bin/env bash
# test-e2e.sh — End-to-end integration test for NetBoot Catalog
# 
# Downloads a real ISO, runs import, validates output, generates menu.
# Requires: root (for mount), internet access, ~2GB free disk space.
#
# Usage:
#   sudo ./tests/test-e2e.sh
#   sudo ./tests/test-e2e.sh --iso /path/to/existing.iso   # skip download
#   sudo ./tests/test-e2e.sh --keep                        # don't cleanup after

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NBC="$PROJECT_ROOT/scripts/nbc"
TEST_BASE_URL="http://10.0.0.1/catalog"

# Debian Live Standard — small (~1.5GB), well-structured
ISO_URL="https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.6.0-amd64-standard.iso"
ISO_FILE=""
KEEP=false
PASSED=0
FAILED=0
TOTAL=0

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)   ISO_FILE="$2"; shift 2 ;;
        --keep)  KEEP=true; shift ;;
        --url)   ISO_URL="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: sudo $0 [--iso <path>] [--url <url>] [--keep]"
            echo ""
            echo "Options:"
            echo "  --iso <path>   Use existing ISO (skip download)"
            echo "  --url <url>    Download ISO from this URL instead of default"
            echo "  --keep         Don't cleanup test artifacts after"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- Test helpers ---
log()  { echo -e "${YELLOW}[test]${NC} $*"; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((PASSED++)); ((TOTAL++)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ((FAILED++)); ((TOTAL++)); }

assert_file_exists() {
    if [[ -f "$1" ]]; then
        pass "$2"
    else
        fail "$2 — file not found: $1"
    fi
}

assert_dir_exists() {
    if [[ -d "$1" ]]; then
        pass "$2"
    else
        fail "$2 — directory not found: $1"
    fi
}

assert_command_succeeds() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc — command failed: $*"
    fi
}

assert_output_contains() {
    local desc="$1"
    local pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    if echo "$output" | grep -qE "$pattern"; then
        pass "$desc"
    else
        fail "$desc — pattern '$pattern' not found in output"
        echo "  Output: $output" | head -5
    fi
}

assert_file_size_gt() {
    local file="$1"
    local min_bytes="$2"
    local desc="$3"
    if [[ -f "$file" ]]; then
        local size
        size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo 0)
        if [[ $size -gt $min_bytes ]]; then
            pass "$desc (${size} bytes)"
        else
            fail "$desc — file too small: ${size} bytes (expected >${min_bytes})"
        fi
    else
        fail "$desc — file not found: $file"
    fi
}

# --- Pre-flight checks ---
log "=== NetBoot Catalog — End-to-End Test ==="
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "This test requires root (for mount -o loop)."
    echo "Run: sudo $0"
    exit 1
fi

# Check dependencies
log "Checking dependencies..."
for cmd in mount umount sha256sum wget; do
    assert_command_succeeds "dependency: $cmd" command -v "$cmd"
done

if command -v yq >/dev/null; then
    pass "dependency: yq"
else
    fail "dependency: yq — not installed"
    echo ""
    echo "Install yq:"
    echo "  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq"
    exit 1
fi

# Check nbc exists
assert_file_exists "$NBC" "nbc CLI exists"
echo ""

# --- Setup test catalog directory ---
export CATALOG_DIR="$PROJECT_ROOT/catalog"
rm -rf "$CATALOG_DIR"
mkdir -p "$CATALOG_DIR"

# --- Download ISO ---
if [[ -z "$ISO_FILE" ]]; then
    ISO_FILE="/tmp/nbc-test-$(basename "$ISO_URL")"
    if [[ -f "$ISO_FILE" ]]; then
        log "ISO already downloaded: $ISO_FILE"
    else
        log "Downloading test ISO (~1.5GB)..."
        log "  URL: $ISO_URL"
        if wget -q --show-progress -O "$ISO_FILE" "$ISO_URL"; then
            pass "ISO download"
        else
            fail "ISO download — wget failed"
            exit 1
        fi
    fi
else
    log "Using provided ISO: $ISO_FILE"
fi

assert_file_exists "$ISO_FILE" "ISO file exists"
assert_file_size_gt "$ISO_FILE" 100000000 "ISO file size > 100MB"
echo ""

# --- Test 1: nbc status (empty catalog) ---
log "Test: nbc status (empty catalog)"
assert_output_contains "nbc status shows 0 entries" "Entries:.*0" "$NBC" status
echo ""

# --- Test 2: nbc validate (adapters only, no entries) ---
log "Test: nbc validate (adapters)"
assert_output_contains "nbc validate passes for adapters" "OK" "$NBC" validate
echo ""

# --- Test 3: nbc import ---
log "Test: nbc import"
IMPORT_OUTPUT=$("$NBC" import "$ISO_FILE" 2>&1) || true

if echo "$IMPORT_OUTPUT" | grep -q "Done!"; then
    pass "nbc import succeeded"
else
    fail "nbc import — did not complete successfully"
    echo "$IMPORT_OUTPUT"
    echo ""
    echo "=== Import failed. Aborting remaining tests. ==="
    echo ""
    echo "Debug: mount the ISO manually and check structure:"
    echo "  mount -o loop,ro $ISO_FILE /mnt && find /mnt -maxdepth 2 | head -30"
    echo ""
    # Print summary so far
    echo -e "\n${YELLOW}=== Results: ${PASSED} passed, ${FAILED} failed, ${TOTAL} total ===${NC}"
    exit 1
fi

# Check import output details
assert_output_contains "import detected distro" "Matched:" echo "$IMPORT_OUTPUT"
assert_output_contains "import extracted kernel" "Extracting kernel" echo "$IMPORT_OUTPUT"
assert_output_contains "import extracted initrd" "Extracting initrd" echo "$IMPORT_OUTPUT"
assert_output_contains "import extracted rootfs" "Extracting rootfs" echo "$IMPORT_OUTPUT"
assert_output_contains "import validation passed" "Validation passed" echo "$IMPORT_OUTPUT"
echo ""

# --- Test 4: Catalog entry created ---
log "Test: catalog entry exists"
ENTRY_DIR=$(find "$CATALOG_DIR" -maxdepth 1 -mindepth 1 -type d | head -1)

if [[ -n "$ENTRY_DIR" ]]; then
    pass "catalog entry directory created: $(basename "$ENTRY_DIR")"
else
    fail "no catalog entry directory found"
    exit 1
fi

assert_file_exists "$ENTRY_DIR/recipe.yaml" "recipe.yaml exists"
assert_file_size_gt "$ENTRY_DIR/$(yq '.assets.kernel' "$ENTRY_DIR/recipe.yaml")" 1000000 "kernel file > 1MB"
assert_file_size_gt "$ENTRY_DIR/$(yq '.assets.initrd' "$ENTRY_DIR/recipe.yaml")" 1000000 "initrd file > 1MB"
assert_file_size_gt "$ENTRY_DIR/$(yq '.assets.rootfs' "$ENTRY_DIR/recipe.yaml")" 10000000 "rootfs file > 10MB"
echo ""

# --- Test 5: recipe.yaml content ---
log "Test: recipe.yaml content"
assert_output_contains "recipe has schema_version" "schema_version" cat "$ENTRY_DIR/recipe.yaml"
assert_output_contains "recipe has id" "^id:" cat "$ENTRY_DIR/recipe.yaml"
assert_output_contains "recipe has distribution" "distribution:" cat "$ENTRY_DIR/recipe.yaml"
assert_output_contains "recipe has boot.default" "default:" cat "$ENTRY_DIR/recipe.yaml"
assert_output_contains "recipe has source_iso_sha256" "source_iso_sha256:" cat "$ENTRY_DIR/recipe.yaml"
echo ""

# --- Test 6: nbc list ---
log "Test: nbc list"
assert_output_contains "nbc list shows entry" "$(yq '.id' "$ENTRY_DIR/recipe.yaml")" "$NBC" list
echo ""

# --- Test 7: nbc generate ---
log "Test: nbc generate"
MENU_FILE="/tmp/nbc-test-menu.ipxe"
rm -f "$MENU_FILE"

if "$NBC" generate --output "$MENU_FILE" --base-url "$TEST_BASE_URL"; then
    pass "nbc generate succeeded"
else
    fail "nbc generate failed"
fi

assert_file_exists "$MENU_FILE" "iPXE menu file created"
assert_output_contains "menu has iPXE shebang" "^#!ipxe" cat "$MENU_FILE"
assert_output_contains "menu has kernel line" "^kernel " cat "$MENU_FILE"
assert_output_contains "menu has initrd line" "^initrd " cat "$MENU_FILE"
assert_output_contains "menu has boot line" "^boot$" cat "$MENU_FILE"
assert_output_contains "menu has base_url" "$TEST_BASE_URL" cat "$MENU_FILE"
echo ""

# --- Test 8: nbc validate (with entries) ---
log "Test: nbc validate (full)"
assert_output_contains "nbc validate all passed" "All checks passed" "$NBC" validate
echo ""

# --- Cleanup ---
if ! $KEEP; then
    log "Cleaning up test artifacts..."
    rm -rf "$CATALOG_DIR"
    rm -f "$MENU_FILE"
    # Don't delete ISO — user might want to reuse it
    log "  (ISO kept at: $ISO_FILE)"
fi

# --- Summary ---
echo ""
echo "═══════════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED: ${PASSED}/${TOTAL}${NC}"
else
    echo -e "${RED}TESTS FAILED: ${FAILED}/${TOTAL} failed${NC}"
fi
echo "═══════════════════════════════════════════════════"
echo ""

# Show generated menu for inspection
if [[ -f "$MENU_FILE" ]]; then
    echo "Generated iPXE menu:"
    echo "---"
    cat "$MENU_FILE"
    echo "---"
fi

exit $FAILED
