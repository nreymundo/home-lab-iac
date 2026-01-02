#!/bin/bash
set -euo pipefail

# Generate autoinstall config (user-data or ks.cfg) with injected SSH keys
# Usage: generate-autoinstall.sh <template-file> <output-file>

TEMPLATE_FILE="$1"
OUTPUT_FILE="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Generating autoinstall config from template..."
echo "    Template: $TEMPLATE_FILE"
echo "    Output:   $OUTPUT_FILE"

# Auto-detect format based on filename
if [[ "$TEMPLATE_FILE" == *ks.cfg.template ]]; then
    FORMAT="kickstart"
    echo "    Format:   Kickstart (Fedora)"
elif [[ "$TEMPLATE_FILE" == *user-data.template ]]; then
    FORMAT="cloudinit"
    echo "    Format:   Cloud-init (Ubuntu)"
else
    echo "ERROR: Cannot determine format from template filename" >&2
    exit 1
fi

# Fetch SSH keys from Bitwarden
echo "==> Fetching SSH keys from Bitwarden..."
SSH_KEYS=$("$SCRIPT_DIR/fetch-ssh-keys.sh" "$FORMAT")

if [[ -z "$SSH_KEYS" ]]; then
    echo "ERROR: Failed to fetch SSH keys" >&2
    exit 1
fi

# Replace {{SSH_KEYS}} placeholder in template
# Use line-by-line processing to handle multi-line SSH keys
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

while IFS= read -r line; do
    if [[ "$line" == *"{{SSH_KEYS}}"* ]]; then
        # Replace the placeholder with the SSH keys
        echo "$SSH_KEYS"
    else
        echo "$line"
    fi
done < "$TEMPLATE_FILE" > "$TEMP_FILE"

mv "$TEMP_FILE" "$OUTPUT_FILE"

echo "==> Autoinstall config generated successfully"
