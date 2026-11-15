#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: plugins.sh [check|apply] [--host HOST] [--manifest PATH] [--only NAME-OR-FILENAME]

Check is the default and exits 2 on drift. The manifest is authoritative for
user-installed plugins: undeclared user plugins are removed on apply.
Stock plugins are excluded. Installed declared plugins are not upgraded.
--only limits reconciliation to the matching declared or installed plugin.
EOF
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
manifest="$script_dir/../plugins.yaml"
host=unraid
mode=check
only=
mode_seen=0
while (($#)); do
  case "$1" in
    check | apply)
      if ((mode_seen)); then
        echo 'Only one mode may be specified' >&2
        exit 1
      fi
      mode=$1
      mode_seen=1
      shift
      ;;
    --host | --manifest | --only)
      if (($# < 2)) || [[ -z $2 || $2 == --* ]]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      case "$1" in
        --host) host=$2 ;;
        --manifest) manifest=$2 ;;
        --only) only=$2 ;;
      esac
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Validate all entries before filtering or contacting the host.
if ! manifest_json=$(yq -o=json '.' "$manifest"); then
  echo 'Unable to parse plugin manifest' >&2
  exit 1
fi
if ! payload=$(
  python3 - "$manifest_json" "$only" << 'PY'
import base64
import json
import re
import sys
from urllib.parse import urlsplit
def mapping(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate key: {key}")
        result[key] = value
    return result
try:
    document = json.loads(sys.argv[1], object_pairs_hook=mapping)
    if not isinstance(document, dict) or set(document) != {"plugins"} or not isinstance(document["plugins"], list):
        raise ValueError("manifest must contain a plugins list")
    filenames, names = set(), set()
    for item in document["plugins"]:
        if not isinstance(item, dict) or set(item) != {"filename", "name", "source", "state"}:
            raise ValueError("each plugin must have filename, name, source, and state")
        if not all(isinstance(value, str) and value for value in item.values()):
            raise ValueError("all plugin fields must be nonempty strings")
        filename, name, source = item["filename"], item["name"], item["source"]
        if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*\.plg", filename) or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", name):
            raise ValueError(f"unsafe plugin filename or name: {filename!r}, {name!r}")
        if filename in filenames or name in names:
            raise ValueError(f"duplicate plugin filename or name: {filename}, {name}")
        if filename in {"unRAIDServer.plg", "unRAIDServer-.plg"} or name in {"unRAIDServer", "unRAIDServer-"}:
            raise ValueError("stock Unraid plugins cannot be managed")
        filenames.add(filename)
        names.add(name)
        url = urlsplit(source)
        if url.scheme != "https" or not url.hostname or url.username is not None or url.password is not None or any(c.isspace() or ord(c) < 32 for c in source):
            raise ValueError(f"source must be an HTTPS URL: {filename}")
        if item["state"] not in {"present", "absent"}:
            raise ValueError(f"invalid state: {filename}")
    only = sys.argv[2]
    if only and not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", only):
        raise ValueError("--only must be a plugin name or filename")
    request = {"plugins": document["plugins"], "only": only}
    print(base64.b64encode(json.dumps(request, separators=(",", ":")).encode()).decode())
except (OSError, ValueError, TypeError) as error:
    print(f"Invalid plugin manifest: {error}", file=sys.stderr)
    sys.exit(1)
PY
); then
  exit 1
fi

status=0
ssh -- "$host" bash -s -- "$mode" "$payload" << 'REMOTE' || status=$?
set -Eeuo pipefail
trap 'exit 1' ERR
mode=$1
request=$(printf '%s' "$2" | base64 -d)
entries=$(printf '%s' "$request" | jq -c '.plugins')
only=$(printf '%s' "$request" | jq -r '.only')
# Persistent plugin manifests identify user plugins; stock registrations live elsewhere.
live=$(
  shopt -s nullglob
  for persistent in /boot/config/plugins/*.plg; do
    filename=${persistent##*/}
    case "$filename" in unRAIDServer.plg|unRAIDServer-.plg) continue ;; esac
    if [[ -L $persistent || ! -f $persistent ]]; then
      echo "Unsafe persistent plugin path: $persistent" >&2; exit 1
    fi
    registration="/var/log/plugins/$filename"
    if [[ -e $registration || -L $registration ]]; then
      if [[ ! -L $registration ]]; then
        echo "Unsafe plugin registration: $registration" >&2; exit 1
      fi
      target=$(readlink -m -- "$registration")
      if [[ $target != "$persistent" ]]; then
        # Never remove a stock plugin through a shadowing boot manifest.
        [[ $target == /boot/config/plugins/* ]] || continue
        echo "Plugin registration points to a different user manifest: $registration" >&2; exit 1
      fi
    fi
    name=$(plugin name "$persistent")
    case "$name" in unRAIDServer|unRAIDServer-) continue ;; esac
    if [[ ! $filename =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*\.plg$ || ! $name =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]; then
      echo "Unsafe installed plugin identity: $filename" >&2; exit 1
    fi
    printf '%s\t%s\n' "$filename" "$name"
  done | jq -Rnc '[inputs | split("\t") | {filename: .[0], name: .[1]}]'
)
if ! jq -en --argjson live "$live" --argjson entries "$entries" '
  ($live | map(.name) | length == (unique | length)) and
  all($live[]; . as $installed |
    all($entries[];
      if .filename == $installed.filename or .name == $installed.name
      then .filename == $installed.filename and .name == $installed.name
      else true end))
' >/dev/null; then
  echo 'Installed plugin identities conflict with the manifest' >&2; exit 1
fi
selected=$(printf '%s' "$entries" | jq -c --arg only "$only" '
  [.[] | select($only == "" or .name == $only or .filename == $only)]')
installed=$(printf '%s' "$live" | jq -c --arg only "$only" '
  [.[] | select($only == "" or .name == $only or .filename == $only)]')
if [[ -n $only && $selected == '[]' && $installed == '[]' ]]; then
  echo "No declared or installed user plugin matches $only" >&2
  printf '%s changed=0\n' "$mode"
  exit 0
fi
plan=$(jq -cn --argjson selected "$selected" --argjson installed "$installed" '
  $selected + [$installed[] | . as $plugin |
    select(all($selected[]; .filename != $plugin.filename)) |
    . + {source: "-", state: "absent"}]')
changed=0
declare -a filenames names sources actions

# Inspect every selected registration before performing any mutations.
while IFS=$'\t' read -r filename name source state; do
  persistent="/boot/config/plugins/$filename"
  registration="/var/log/plugins/$filename"
  if [[ -L $persistent || ( -e $persistent && ! -f $persistent ) ]]; then
    echo "Unsafe persistent plugin path: $persistent" >&2; exit 1
  fi
  if [[ -e $registration || -L $registration ]]; then
    if [[ ! -L $registration || $(readlink -m -- "$registration") != "$persistent" ]]; then
      echo "Registration is outside the persistent plugin path: $registration" >&2; exit 1
    fi
  fi
  if [[ -f $persistent ]]; then
    actual=$(plugin name "$persistent") || exit 1
    if [[ $actual != "$name" ]]; then
      echo "Plugin identity mismatch for $filename: $actual != $name" >&2; exit 1
    fi
  fi
  action=none
  if [[ $state == present ]]; then
    if [[ ! -f $persistent || ! -L $registration || ! -e $registration ]]; then action=install; fi
  elif [[ -e $persistent || -L $registration ]]; then
    action=remove
  fi
  filenames+=("$filename"); names+=("$name"); sources+=("$source"); actions+=("$action")
done < <(printf '%s' "$plan" | jq -r '.[] | [.filename, .name, .source, .state] | @tsv')

for i in "${!filenames[@]}"; do
  filename=${filenames[i]}; name=${names[i]}; action=${actions[i]}
  [[ $action != none ]] || continue
  changed=$((changed + 1))
  echo "$action $filename ($name)"
  [[ $mode == apply ]] || continue
  persistent="/boot/config/plugins/$filename"
  registration="/var/log/plugins/$filename"
  if [[ $action == install ]]; then
    if [[ -f $persistent ]]; then
      plugin install "$persistent"
    else
      temp=$(mktemp -d)
      trap 'rm -rf -- "$temp"' EXIT
      curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --output "$temp/$filename" "${sources[i]}"
      actual=$(plugin name "$temp/$filename")
      if [[ $actual != "$name" ]]; then
        echo "Downloaded plugin identity mismatch for $filename: $actual != $name" >&2; exit 1
      fi
      plugin install "$temp/$filename"
      rm -rf -- "$temp"
      trap - EXIT
    fi
    if [[ ! -f $persistent || ! -L $registration || $(readlink -m -- "$registration") != "$persistent" || $(plugin name "$persistent") != "$name" ]]; then
      echo "Plugin registration verification failed: $filename" >&2; exit 1
    fi
  else
    # The native remove command needs a registration even for a boot-only file.
    if [[ -f $persistent && ! -L $registration ]]; then ln -s -- "$persistent" "$registration"; fi
    plugin remove "$filename"
    if [[ -e $persistent || -e $registration || -L $registration ]]; then
      echo "Plugin removal verification failed: $filename" >&2; exit 1
    fi
  fi
done
printf '%s changed=%s\n' "$mode" "$changed"
if [[ $mode == check && $changed -gt 0 ]]; then exit 2; fi
REMOTE
case $status in
  0) exit 0 ;;
  2)
    [[ $mode == check ]] && exit 2
    exit 1
    ;;
  *) exit 1 ;;
esac
