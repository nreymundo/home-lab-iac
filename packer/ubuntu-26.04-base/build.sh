#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

"$script_dir/../scripts/build-ubuntu-template.sh" "$script_dir" "$@"
