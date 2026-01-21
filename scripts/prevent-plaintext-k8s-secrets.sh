#!/usr/bin/env bash
set -euo pipefail

mapfile -t files < <(git diff --cached --name-only --diff-filter=ACM | rg -i '\.ya?ml$' || true)
[ ${#files[@]} -eq 0 ] && exit 0

fail=0

for f in "${files[@]}"; do
  # Allow encrypted secret files by convention
  if [[ "$f" =~ \.sops\.ya?ml$ ]]; then
    continue
  fi

  # If it's a Kubernetes Secret manifest, fail hard.
  # (Policy: Secrets must be committed only as *.sops.yaml)
  if rg -n '^\s*kind:\s*Secret\s*$' "$f" >/dev/null 2>&1; then
    echo "ERROR: Plaintext Kubernetes Secret detected in: $f"
    echo "       Rename to *.sops.yaml and encrypt with sops."
    fail=1
  fi
done

exit $fail
