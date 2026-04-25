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
import subprocess
import pathlib
import re
import sys

message_path = pathlib.Path(sys.argv[1])
allowed_subject = re.compile(
    r"^(feat|fix|docs|refactor|chore)(\([a-z0-9][a-z0-9+._/-]*\))?: \S.*$"
)
git_generated_subjects = [
    re.compile(r"^Merge\b"),
    re.compile(r'^Revert ".+"$'),
    re.compile(r"^(fixup|squash|amend)! "),
]
forbidden = [
    re.compile(r"^Co-authored-by:\s*Sisyphus\b", re.IGNORECASE),
    re.compile(r"^Ultraworked with\b", re.IGNORECASE),
    re.compile(r"^Co-authored-by:.*clio-agent@sisyphuslabs\.ai\b", re.IGNORECASE),
]


def get_comment_prefix() -> str:
    for key in ("core.commentString", "core.commentChar"):
        try:
            value = subprocess.check_output(
                ["git", "config", "--get", key],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
        if value and value != "auto":
            return value
    return "#"


comment_prefix = get_comment_prefix()
subject_line = None

violations = []
for line_number, raw_line in enumerate(message_path.read_text().splitlines(), start=1):
    line = raw_line.rstrip("\r")
    if line.startswith(comment_prefix):
        continue
    if subject_line is None and line.strip():
        subject_line = line
    if any(pattern.search(line) for pattern in forbidden):
        violations.append((line_number, line))

if subject_line and not any(pattern.search(subject_line) for pattern in git_generated_subjects):
    if not allowed_subject.fullmatch(subject_line):
        print("ERROR: commit message subject must match '<type>(<scope>): <description>' or '<type>: <description>'.", file=sys.stderr)
        print("Allowed types: feat, fix, docs, refactor, chore.", file=sys.stderr)
        print("Examples: 'chore(ansible): install packages', 'refactor(helm): simplify values', 'docs: update guide'.", file=sys.stderr)
        print("Allowed Git-generated subjects: Merge ..., Revert \"...\", fixup! ..., squash! ..., amend! ...", file=sys.stderr)
        print("", file=sys.stderr)
        print(f"subject: {subject_line}", file=sys.stderr)
        sys.exit(1)

if violations:
    print("ERROR: commit message contains forbidden Sisyphus attribution text.", file=sys.stderr)
    print("This repository forbids the 'Co-authored-by: Sisyphus' trailer, 'Ultraworked with ...' footer, and the clio-agent@sisyphuslabs.ai email.", file=sys.stderr)
    print("Remove those specific attribution markers before committing.", file=sys.stderr)
    print("", file=sys.stderr)
    for line_number, line in violations:
        print(f"line {line_number}: {line}", file=sys.stderr)
    sys.exit(1)
PY
