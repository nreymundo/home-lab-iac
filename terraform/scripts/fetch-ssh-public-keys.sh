#!/bin/bash
set -euo pipefail

# Fetch SSH public keys from 1Password for the hashicorp/external data source.
#
# Protocol: reads one JSON query object from stdin and must print exactly one
# JSON object to stdout. The query must contain a non-empty string field "tag".
# The result object has a single string field "keys" holding the public keys,
# one per line.
#
# Vault scope:
# - OP_SSH_KEYS_VAULT_ID set: only that vault ID is searched.
# - OP_SSH_KEYS_VAULT_ID unset: all vaults accessible to the authenticated
#   account are searched.
#
# Authentication: whatever the op CLI normally uses (desktop app integration
# or an authenticated session); OP_ACCOUNT is honored natively by op.
#
# All diagnostics go to stderr; stdout carries only the result JSON object.

die() {
	echo "ERROR: $*" >&2
	exit 1
}

command -v op &>/dev/null || die "1Password CLI (op) not found"
command -v jq &>/dev/null || die "jq not found"

QUERY=$(cat)

if ! jq -e '.' >/dev/null 2>&1 <<<"$QUERY"; then
	die "malformed JSON query on stdin"
fi

TAG=$(jq -er '.tag // empty | select(type == "string" and length > 0)' 2>/dev/null <<<"$QUERY") ||
	die "query must include a non-empty string field 'tag'"

OP_ITEM_LIST_ARGS=()
if [[ -n "${OP_SSH_KEYS_VAULT_ID:-}" ]]; then
	OP_ITEM_LIST_ARGS=(--vault "$OP_SSH_KEYS_VAULT_ID")
fi

if ! ITEMS_JSON=$(op item list "${OP_ITEM_LIST_ARGS[@]}" --categories "SSH Key" --tags "$TAG" --format json); then
	die "failed to list 1Password SSH Key items tagged '$TAG' (check op authentication)"
fi

if ! ITEM_REFS=$(jq -r 'sort_by(.vault.id, .id) | .[] | "\(.vault.id)\t\(.id)"' 2>/dev/null <<<"$ITEMS_JSON"); then
	die "failed to parse 1Password item list"
fi

[[ -n "$ITEM_REFS" ]] || die "no 1Password SSH Key items tagged '$TAG' found"

KEYS=""
while IFS=$'\t' read -r vault_id item_id; do
	if ! PUBLIC_KEY=$(op read "op://$vault_id/$item_id/public key"); then
		die "missing public key field on 1Password item $item_id in vault $vault_id"
	fi

	[[ -n "$PUBLIC_KEY" ]] || die "empty public key field on 1Password item $item_id in vault $vault_id"

	KEYS+="$PUBLIC_KEY"$'\n'
done <<<"$ITEM_REFS"

# Drop the trailing newline and require at least one key
KEYS="${KEYS%$'\n'}"
[[ -n "${KEYS//[[:space:]]/}" ]] || die "no SSH public keys retrieved from 1Password"

jq -cn --arg keys "$KEYS" '{keys: $keys}'
