#!/bin/bash
set -euo pipefail

# Fetch SSH public keys from 1Password for the hashicorp/external data source.
#
# Protocol: reads one JSON query object from stdin and must print exactly one
# JSON object to stdout. The query must contain a non-empty string field "tag".
# The result object has a single string field "keys" holding the public keys,
# one per line.
#
# Required environment:
# - OP_SERVICE_ACCOUNT_TOKEN: 1Password service account token; the op CLI
#   authenticates with it natively.
# - IAC_1PASSWORD_VAULT_ID: vault ID used for both item listing and field
#   reading; there is no all-vault fallback.
#
# All diagnostics go to stderr; stdout carries only the result JSON object.

die() {
	echo "ERROR: $*" >&2
	exit 1
}

command -v op &>/dev/null || die "1Password CLI (op) not found"
command -v jq &>/dev/null || die "jq not found"

[[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] || die "OP_SERVICE_ACCOUNT_TOKEN must be set to a 1Password service account token"
[[ -n "${IAC_1PASSWORD_VAULT_ID:-}" ]] || die "IAC_1PASSWORD_VAULT_ID must be set to the 1Password vault ID"

QUERY=$(cat)

if ! jq -e '.' >/dev/null 2>&1 <<<"$QUERY"; then
	die "malformed JSON query on stdin"
fi

TAG=$(jq -er '.tag // empty | select(type == "string" and length > 0)' 2>/dev/null <<<"$QUERY") ||
	die "query must include a non-empty string field 'tag'"

if ! ITEMS_JSON=$(op item list --vault "$IAC_1PASSWORD_VAULT_ID" --categories "SSH Key" --tags "$TAG" --format json); then
	die "failed to list 1Password SSH Key items tagged '$TAG' in vault $IAC_1PASSWORD_VAULT_ID (check OP_SERVICE_ACCOUNT_TOKEN access to the vault)"
fi

if ! ITEM_IDS=$(jq -r 'sort_by(.vault.id, .id) | .[].id' 2>/dev/null <<<"$ITEMS_JSON"); then
	die "failed to parse 1Password item list"
fi

[[ -n "$ITEM_IDS" ]] || die "no 1Password SSH Key items tagged '$TAG' found"

KEYS=""
while IFS= read -r item_id; do
	if ! PUBLIC_KEY=$(op read "op://$IAC_1PASSWORD_VAULT_ID/$item_id/public key"); then
		die "missing public key field on 1Password item $item_id in vault $IAC_1PASSWORD_VAULT_ID"
	fi

	[[ -n "$PUBLIC_KEY" ]] || die "empty public key field on 1Password item $item_id in vault $IAC_1PASSWORD_VAULT_ID"

	KEYS+="$PUBLIC_KEY"$'\n'
done <<<"$ITEM_IDS"

# Drop the trailing newline and require at least one key
KEYS="${KEYS%$'\n'}"
[[ -n "${KEYS//[[:space:]]/}" ]] || die "no SSH public keys retrieved from 1Password"

jq -cn --arg keys "$KEYS" '{keys: $keys}'
