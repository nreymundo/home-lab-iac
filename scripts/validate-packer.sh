#!/usr/bin/env bash
# Validate the Packer templates affected by the current uncommitted diff.
#
# A "template" is any directory directly under packer/ that contains
# *.pkr.hcl files. Only templates whose files changed are validated.
#
# Network access is required for plugin downloads.
# Run from the repository root. Use --all to force validation of every template.
set -euo pipefail

readonly PACKER_ROOT="packer"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

command_exists git || { echo "ERROR: git is required." >&2; exit 1; }
command_exists packer || { echo "ERROR: packer is required." >&2; exit 1; }

if [[ ! -d "$PACKER_ROOT" ]]; then
  echo "ERROR: run this script from the repository root." >&2
  exit 1
fi

force_all=false
if [[ "${1:-}" == "--all" ]]; then
  force_all=true
fi

discover_all_templates() {
  # Templates are directories containing at least one *.pkr.hcl file.
  # --cached --others --exclude-standard includes untracked-but-not-ignored files
  # so newly added templates are seen by --all and the qualification filter below.
  # The existence filter drops tracked files deleted from the working tree
  # (unstaged removals) so removed templates are not reported.
  git ls-files --cached --others --exclude-standard "$PACKER_ROOT/**/*.pkr.hcl" \
    | while IFS= read -r f; do if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi; done \
    | xargs -r -n1 dirname \
    | sort -u
}

if [[ "$force_all" == "true" ]]; then
  mapfile -t templates < <(discover_all_templates)
  if [[ ${#templates[@]} -eq 0 ]]; then
    echo "Packer: no templates found."
    exit 0
  fi
  echo "Packer: --all mode, validating ${#templates[@]} template(s)."
else
  mapfile -t status_lines < <(git status --porcelain=v1 --untracked-files=all)

  declare -A affected_templates=()

  for line in "${status_lines[@]}"; do
    field="${line:3}"
    if [[ "$field" == *" -> "* ]]; then
      # Handle rename: "R  old -> new". Process BOTH sides so a move OUT of a
      # template still surfaces the now-broken source (mirrors the deletion case).
      paths=( "${field%% -> *}" "${field##* -> }" )
    else
      paths=( "$field" )
    fi
    for path in "${paths[@]}"; do
      if [[ "$path" != "$PACKER_ROOT"/* ]]; then
        continue
      fi
      # Any change inside packer/<template>/ affects that template, since
      # scripts, http/autoinstall files, and variable files are all part of it.
      # Deletions are included: a surviving template may now be broken, while a
      # template emptied of its last *.pkr.hcl is filtered out below.
      rel="${path#$PACKER_ROOT/}"
      template_name="${rel%%/*}"
      [[ -n "$template_name" ]] && affected_templates["$PACKER_ROOT/$template_name"]=1
    done
  done

  if [[ ${#affected_templates[@]} -gt 0 ]]; then
    # Filter to templates that actually contain *.pkr.hcl (e.g. ignore scripts/ at root).
    mapfile -t candidates < <(printf '%s\n' "${!affected_templates[@]}" | sort)
    declare -A real_templates=()
    all_template_dirs="$(discover_all_templates)"
    for c in "${candidates[@]}"; do
      if printf '%s\n' "$all_template_dirs" | grep -qx "$c"; then
        real_templates["$c"]=1
      fi
    done
    if [[ ${#real_templates[@]} -eq 0 ]]; then
      echo "Packer: no template changes detected; nothing to validate."
      exit 0
    fi
    mapfile -t templates < <(printf '%s\n' "${!real_templates[@]}" | sort)
    echo "Packer: validating ${#templates[@]} affected template(s)."
  else
    echo "Packer: no changes detected; nothing to validate."
    exit 0
  fi
fi

failures=0
for template in "${templates[@]}"; do
  echo "Validating $template"
  if ! packer init "$template" >/tmp/packer-init.log 2>&1; then
    echo "  init failed for $template:" >&2
    cat /tmp/packer-init.log >&2
    failures=$((failures + 1))
    continue
  fi
  if ! packer validate "$template"; then
    failures=$((failures + 1))
  fi
done

rm -f /tmp/packer-init.log

if [[ "$failures" -ne 0 ]]; then
  echo "ERROR: $failures Packer template(s) failed validation." >&2
  exit 1
fi

echo "Packer: ${#templates[@]} template(s) validated."
