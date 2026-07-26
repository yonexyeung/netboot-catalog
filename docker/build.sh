#!/usr/bin/env bash
# Build the NetBoot Catalog Docker image.
# Must be run from project root, or this script handles it for you.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"
docker build -t netboot-catalog -f docker/Dockerfile .
