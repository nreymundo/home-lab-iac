#!/bin/bash
set -euo pipefail

# Fetch SSH public keys from Bitwarden Secrets Manager
# Usage: fetch-ssh-keys.sh [cloudinit|kickstart]
# Requires: BWS_ACCESS_TOKEN environment variable

FORMAT="${1:-cloudinit}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for BWS_ACCESS_TOKEN
if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
    echo "ERROR: BWS_ACCESS_TOKEN environment variable not set" >&2
    echo "Export it: export BWS_ACCESS_TOKEN='your-token'" >&2
    exit 1
fi

# Check for bws CLI
if ! command -v bws &> /dev/null; then
    echo "ERROR: bws CLI not found" >&2
    echo "Install: yay -S bws-bin (Arch) or cargo install bws" >&2
    exit 1
fi

# Load secret ID
if [[ ! -f "$SCRIPT_DIR/bws-config.sh" ]]; then
    echo "ERROR: $SCRIPT_DIR/bws-config.sh not found" >&2
    exit 1
fi

source "$SCRIPT_DIR/bws-config.sh"

# Fetch all SSH keys from single secret
KEYS_RAW=$(bws secret get "$BWS_SSH_KEYS_ID" --access-token "$BWS_ACCESS_TOKEN" 2>/dev/null | jq -r '.value')

# Validate keys were fetched
if [[ -z "$KEYS_RAW" ]]; then
    echo "ERROR: Failed to fetch SSH keys from Bitwarden" >&2
    exit 1
fi

# Format output based on target system
if [[ "$FORMAT" == "cloudinit" ]]; then
    # Ubuntu cloud-init format (YAML array with proper indentation)
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue  # Skip empty lines
        echo "      - \"$key\""
    done <<< "$KEYS_RAW"

elif [[ "$FORMAT" == "kickstart" ]]; then
    # Fedora Kickstart format (multiple sshkey directives)
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue  # Skip empty lines
        echo "sshkey --username=fedora \"$key\""
    done <<< "$KEYS_RAW"

else
    echo "ERROR: Unknown format '$FORMAT'. Use 'cloudinit' or 'kickstart'" >&2
    exit 1
fi
