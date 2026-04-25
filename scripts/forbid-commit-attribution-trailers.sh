#!/usr/bin/env bash

# This is here to stop the noisy "Oh-My-OpenAgent" plugin from appending advertising even when the workspace rules and prompt forbids it.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <commit-message-file>" >&2
  exit 2
fi

message_file="$1"

if [ ! -f "$message_file" ]; then
  echo "ERROR: commit message file not found: $message_file" >&2
  exit 2
fi

python3 - "$message_file" <<'PY'
import pathlib
import re
import sys

message_path = pathlib.Path(sys.argv[1])
forbidden = [
    re.compile(r"^Co-authored-by:\s*Sisyphus\b", re.IGNORECASE),
    re.compile(r"^Ultraworked with\b", re.IGNORECASE),
    re.compile(r"clio-agent@sisyphuslabs\.ai", re.IGNORECASE),
]

violations = []
for line_number, raw_line in enumerate(message_path.read_text().splitlines(), start=1):
    line = raw_line.rstrip("\r")
    if line.startswith("#"):
        continue
    if any(pattern.search(line) for pattern in forbidden):
        violations.append((line_number, line))

if violations:
    print("ERROR: commit message contains forbidden Sisyphus attribution text.", file=sys.stderr)
    print("This repository forbids the 'Co-authored-by: Sisyphus' trailer, 'Ultraworked with ...' footer, and the clio-agent@sisyphuslabs.ai email.", file=sys.stderr)
    print("Remove those specific attribution markers before committing.", file=sys.stderr)
    print("", file=sys.stderr)
    for line_number, line in violations:
        print(f"line {line_number}: {line}", file=sys.stderr)
    sys.exit(1)
PY
