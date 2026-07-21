#!/usr/bin/env bash
# Validate the Terraform roots affected by the current uncommitted diff.
#
# A "root" is any directory under terraform/ (excluding terraform/modules/)
# that contains *.tf files. Only roots whose files changed are validated,
# unless a module under terraform/modules/ changed (then all roots are
# validated, since modules are shared).
#
# Network access is required to download providers from the Terraform Registry.
# Run from the repository root. Use --all to force validation of every root.
set -euo pipefail

export TF_CLI_ARGS_init="-no-color -input=false"
export TF_CLI_ARGS_validate="-no-color"

readonly TERRAFORM_ROOT="terraform"
readonly MODULES_PREFIX="terraform/modules/"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

command_exists git || { echo "ERROR: git is required." >&2; exit 1; }
command_exists terraform || { echo "ERROR: terraform is required." >&2; exit 1; }

if [[ ! -d "$TERRAFORM_ROOT" ]]; then
  echo "ERROR: run this script from the repository root." >&2
  exit 1
fi

force_all=false
if [[ "${1:-}" == "--all" ]]; then
  force_all=true
fi

discover_all_roots() {
  # Roots are directories that contain at least one *.tf file, excluding modules.
  # --cached --others --exclude-standard includes untracked-but-not-ignored files
  # so newly added roots are seen by --all and the module-change fan-out.
  git ls-files --cached --others --exclude-standard "$TERRAFORM_ROOT/**/*.tf" \
    | grep -v "^${MODULES_PREFIX}" \
    | xargs -r -n1 dirname \
    | sort -u
}

if [[ "$force_all" == "true" ]]; then
  mapfile -t roots < <(discover_all_roots)
  if [[ ${#roots[@]} -eq 0 ]]; then
    echo "Terraform: no roots found."
    exit 0
  fi
  echo "Terraform: --all mode, validating ${#roots[@]} root(s)."
else
  # Parse `git status --porcelain` to include staged, unstaged, and untracked files.
  # --untracked-files=all enumerates untracked files individually (not as "?? dir/")
  # so newly added roots are caught by the *.tf filter below.
  mapfile -t status_lines < <(git status --porcelain=v1 --untracked-files=all)

  modules_changed=false
  declare -A affected_roots=()

  for line in "${status_lines[@]}"; do
    path="${line:3}"
    # Handle rename: "R  old -> new"
    if [[ "$path" == *" -> "* ]]; then
      path="${path##* -> }"
    fi
    # Only *.tf files affect validation. tfvars, plans, etc. do not.
    if [[ "$path" != *.tf ]]; then
      continue
    fi
    if [[ "$path" != "$TERRAFORM_ROOT"/* ]]; then
      continue
    fi
    if [[ "$path" == "$MODULES_PREFIX"* ]]; then
      # Module changes (including deletions) may affect every consuming root.
      modules_changed=true
    else
      # Deletions matter too: a surviving root may now be broken. Validate the
      # containing root only if it still exists on disk (a fully removed root is gone).
      [[ -d "${path%/*}" ]] && affected_roots["${path%/*}"]=1
    fi
  done

  if [[ "$modules_changed" == "true" ]]; then
    # A shared module changed: every known root plus any explicitly affected
    # non-module root (e.g. a newly added root in the same diff) may be affected.
    declare -A combined=()
    mapfile -t _discovered < <(discover_all_roots)
    for r in "${_discovered[@]}"; do combined["$r"]=1; done
    for r in "${!affected_roots[@]}"; do combined["$r"]=1; done
    mapfile -t roots < <(printf '%s\n' "${!combined[@]}" | sort)
    echo "Terraform: module change detected, validating ${#roots[@]} root(s)."
  elif [[ ${#affected_roots[@]} -gt 0 ]]; then
    mapfile -t roots < <(printf '%s\n' "${!affected_roots[@]}" | sort)
    echo "Terraform: validating ${#roots[@]} affected root(s)."
  else
    echo "Terraform: no changes detected; nothing to validate."
    exit 0
  fi
fi

failures=0
for root in "${roots[@]}"; do
  echo "Validating $root"
  if ! terraform -chdir="$root" init -backend=false >/tmp/tf-init.log 2>&1; then
    echo "  init failed for $root:" >&2
    cat /tmp/tf-init.log >&2
    failures=$((failures + 1))
    continue
  fi
  if ! terraform -chdir="$root" validate; then
    failures=$((failures + 1))
  fi
done

rm -f /tmp/tf-init.log

if [[ "$failures" -ne 0 ]]; then
  echo "ERROR: $failures Terraform root(s) failed validation." >&2
  exit 1
fi

echo "Terraform: ${#roots[@]} root(s) validated."
