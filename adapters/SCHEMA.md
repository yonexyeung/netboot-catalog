# Boot Recipe Adapter Schema v0.1

## Overview

Each adapter is a YAML file that describes how to detect, extract, and boot a specific Linux distribution from its ISO.

## Schema

```yaml
# Required
schema_version: "1"                # Adapter schema version
id: <string>                       # Unique identifier (e.g. "ubuntu-desktop")
name: <string>                     # Human-readable name
distribution: <string>             # Distro family (e.g. "ubuntu", "debian")
homepage: <url>                    # Distro homepage (optional)
maintainer: <string>               # Adapter maintainer

# Detection rules — all must match for this adapter to activate
detection:
  - file_exists: <path>            # File must exist in mounted ISO
  - file_contains:                 # File must contain string/regex
      path: <path>
      pattern: <string>            # Substring or regex
  # Optional: volume_label match
  - volume_label: <string>

# Extraction — paths relative to ISO mount root
assets:
  kernel: <path>                   # Path to kernel (vmlinuz)
  initrd: <path>                   # Path to initramfs
  rootfs: <path>                   # Path to root filesystem (squashfs/erofs)
  rootfs_type: <string>            # "squashfs" | "erofs" | "iso"

# Boot parameters — use {{variables}} for templating
# Available variables: {{base_url}}, {{kernel_url}}, {{initrd_url}}, {{rootfs_url}}
boot:
  default: <string>                # Default kernel command line
  variants:                        # Optional alternative boot modes
    <name>: <string>               # Variant name → kernel args

# Validation — post-extraction checks
validation:
  required_files:
    - <path>                       # Relative to extracted entry directory
```

## Template Variables

| Variable | Expands to |
|----------|-----------|
| `{{base_url}}` | HTTP base URL of the catalog entry (e.g. `http://10.0.0.1/catalog/ubuntu-2404`) |
| `{{kernel_url}}` | Full URL to kernel file |
| `{{initrd_url}}` | Full URL to initrd file |
| `{{rootfs_url}}` | Full URL to rootfs file |

## Notes

- All `detection` rules are AND-ed (all must match).
- `file_contains.pattern` supports basic regex (grep -E compatible).
- `assets.initrd` can be a single path or a list (for distros with multiple initrd files).
- `boot.variants` is optional. If absent, only `boot.default` is used.
