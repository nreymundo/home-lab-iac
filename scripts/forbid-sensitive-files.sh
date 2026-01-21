#!/usr/bin/env bash
set -euo pipefail

# Check staged files only
files=$(git diff --cached --name-only --diff-filter=ACM || true)
[ -z "${files}" ] && exit 0

# Forbid committing key material by filename
if echo "$files" | rg -n '(^|/)(.*\.agekey|.*\.pem|.*\.key)$' >/dev/null; then
  echo "ERROR: Refusing commit: private key material detected in staged files."
  echo "       Remove it from staging and ensure it is gitignored."
  echo
  echo "$files" | rg '(^|/)(.*\.agekey|.*\.pem|.*\.key)$' || true
  exit 1
fi
