#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <template-dir> [packer build args...]" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
template_dir="$1"
shift

cd "$template_dir"

echo "==> Pre-build: Generating user-data with SSH keys from Bitwarden..."
"$script_dir/generate-autoinstall.sh" http/user-data.template http/user-data

echo "==> Running Packer build..."
packer build "$@" .
