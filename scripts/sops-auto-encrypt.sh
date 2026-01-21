#!/usr/bin/env bash
set -euo pipefail

changed=0
for f in "$@"; do
  if rg -q "^(---[[:space:]]*)?sops:[[:space:]]*$" "$f"; then
    continue
  fi
  sops --encrypt --in-place "$f"
  changed=1
done

if [ "$changed" -eq 1 ]; then
  git add "$@"
fi
