# NetBoot Catalog

> Drop ISO. Network Boot. Open Source.

NetBoot Catalog is a self-hosted platform that normalizes Linux Live ISOs into reusable NetBoot entries. It automates the detection, extraction, and boot menu generation that you'd otherwise do manually for each distro.

**It is not a PXE server replacement.** It is a catalog engine that feeds your PXE infrastructure.

## How It Works

```
ISO file
  → nbc import (detect distro → extract kernel/initrd/rootfs → generate recipe)
  → nbc generate (produce iPXE boot menu)
  → dnsmasq + nginx serve everything
  → PXE client boots
```

## Quick Start (Docker)

```bash
docker build -t netboot-catalog ./docker
docker run -d --network host --cap-add NET_ADMIN \
  -v /srv/import:/srv/import \
  -v /srv/catalog:/srv/catalog \
  netboot-catalog
```

Drop an ISO into `/srv/import/` — it will be auto-imported and available for PXE boot.

## Quick Start (CLI only)

```bash
# Dependencies: bash, yq, mount (root required for ISO mount)

# Import an ISO
./scripts/nbc import ubuntu-24.04-desktop-amd64.iso

# List catalog
./scripts/nbc list

# Generate iPXE menu
./scripts/nbc generate --output /srv/tftp/menu.ipxe --base-url http://10.0.0.1/catalog

# Validate everything
./scripts/nbc validate
```

## Project Structure

```
netboot-catalog/
├── adapters/           # YAML adapter definitions (per distro)
│   ├── SCHEMA.md       # Adapter schema documentation
│   ├── ubuntu-desktop.yaml
│   ├── debian-live.yaml
│   └── vyos.yaml
├── catalog/            # Extracted entries (generated, gitignored)
├── scripts/
│   ├── nbc             # CLI wrapper
│   ├── nbc-import.sh   # Import engine
│   └── nbc-generate.sh # Menu generator
├── templates/          # iPXE menu templates
├── docker/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── dnsmasq.conf
│   └── nginx.conf
└── docs/               # Architecture decisions & reviews
```

## Supported Distros

| Distro | Adapter | Status |
|--------|---------|--------|
| Ubuntu Desktop | `ubuntu-desktop.yaml` | Draft |
| Debian Live | `debian-live.yaml` | Draft |
| VyOS Rolling | `vyos.yaml` | Draft |

## Adding a New Distro

Create a YAML file in `adapters/`:

```yaml
schema_version: "1"
id: my-distro
name: "My Distro Live"
distribution: mydistro

detection:
  - file_exists: path/to/kernel
  - file_contains:
      path: some/file
      pattern: "MyDistro"

assets:
  kernel: path/to/vmlinuz
  initrd: path/to/initrd
  rootfs: path/to/filesystem.squashfs
  rootfs_type: squashfs

boot:
  default: "boot=live fetch={{rootfs_url}}"

validation:
  required_files:
    - vmlinuz
    - initrd
    - filesystem.squashfs
```

No code changes needed. Just add the YAML and re-import.

## Requirements

- Linux (for ISO mounting)
- `yq` (YAML processor)
- `bash` 4+
- Root access (for `mount -o loop`)

## Status

**Prototype.** Not production-ready. Schema and CLI interface may change.

## License

TBD
