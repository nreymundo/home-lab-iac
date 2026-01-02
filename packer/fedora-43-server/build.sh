#!/bin/bash
set -euo pipefail

# Pre-build script: Generate ks.cfg before Packer starts
cd "$(dirname "$0")"

echo "==> Pre-build: Generating ks.cfg with SSH keys from Bitwarden..."
../scripts/generate-autoinstall.sh http/ks.cfg.template http/ks.cfg

echo "==> Running Packer build..."
packer build "$@" .
