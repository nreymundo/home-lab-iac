#!/bin/bash
set -euo pipefail

# Fetch SSH public keys from 1Password
# Usage: fetch-ssh-keys.sh [cloudinit|kickstart]
# Requires: 1Password CLI (op) with an authenticated session or desktop app
# integration, plus jq. Optionally set OP_ACCOUNT to pick a specific account.

FORMAT="${1:-cloudinit}"

readonly OP_VAULT_ID="rpx5om7wm7nhkoq7jsuo6n7gwm"
readonly OP_ITEM_CATEGORY="SSH Key"
readonly OP_ITEM_TAG="packer"

# Check for op CLI
if ! command -v op &>/dev/null; then
	echo "ERROR: 1Password CLI (op) not found" >&2
	echo "Install: sudo pacman -S 1password-cli (Arch) or use the vendor install method" >&2
	exit 1
fi

# Check for jq
if ! command -v jq &>/dev/null; then
	echo "ERROR: jq not found" >&2
	echo "Install: sudo pacman -S jq (Arch) or sudo apt-get install jq (Ubuntu)" >&2
	exit 1
fi

# List SSH key items tagged for Packer, sorted by item ID for a stable key order
if ! ITEM_IDS=$(op item list --vault "$OP_VAULT_ID" --categories "$OP_ITEM_CATEGORY" --tags "$OP_ITEM_TAG" --format json |
	jq -r 'sort_by(.id) | .[].id'); then
	echo "ERROR: Failed to list 1Password SSH key items (check 'op' authentication)" >&2
	exit 1
fi

if [[ -z "$ITEM_IDS" ]]; then
	echo "ERROR: No 1Password SSH key items tagged '$OP_ITEM_TAG' found in vault $OP_VAULT_ID" >&2
	exit 1
fi

# Fetch the public key of each matching item
KEYS_RAW=""
while IFS= read -r item_id; do
	if ! key=$(op read "op://$OP_VAULT_ID/$item_id/public key"); then
		echo "ERROR: Failed to read public key for 1Password item $item_id" >&2
		exit 1
	fi
	KEYS_RAW+="$key"$'\n'
done <<<"$ITEM_IDS"

# Validate keys were fetched
if [[ -z "${KEYS_RAW//[[:space:]]/}" ]]; then
	echo "ERROR: Failed to fetch SSH public keys from 1Password" >&2
	exit 1
fi

# Format output based on target system
if [[ "$FORMAT" == "cloudinit" ]]; then
	# Ubuntu cloud-init format (YAML array with proper indentation)
	while IFS= read -r key; do
		[[ -z "$key" ]] && continue # Skip empty lines
		echo "      - \"$key\""
	done <<<"$KEYS_RAW"

elif [[ "$FORMAT" == "kickstart" ]]; then
	# Fedora Kickstart format (multiple sshkey directives)
	while IFS= read -r key; do
		[[ -z "$key" ]] && continue # Skip empty lines
		echo "sshkey --username=fedora \"$key\""
	done <<<"$KEYS_RAW"

else
	echo "ERROR: Unknown format '$FORMAT'. Use 'cloudinit' or 'kickstart'" >&2
	exit 1
fi
