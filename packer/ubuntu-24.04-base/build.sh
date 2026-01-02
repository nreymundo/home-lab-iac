#!/bin/bash
set -euo pipefail

# Pre-build script: Generate user-data before Packer starts
cd "$(dirname "$0")"

echo "==> Pre-build: Generating user-data with SSH keys from Bitwarden..."
../scripts/generate-autoinstall.sh http/user-data.template http/user-data

echo "==> Running Packer build..."
packer build "$@" .
