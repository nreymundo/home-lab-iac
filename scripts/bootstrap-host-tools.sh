#!/usr/bin/env bash
set -euo pipefail

# Host tools currently expected by this repository.
# git and bash are intentionally omitted because this script assumes they exist.
readonly REQUIRED_TOOLS=(
  pre-commit
  python3
  rg
  sops
  terraform
  packer
  ansible-lint
  kubectl
  flux
  ansible-playbook
  bws
  jq
  yq
)

readonly SUPPORTED_DISTRO_TOKENS=(
  arch
  archlinux
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_ROOT

MODE="check"
AUR_HELPER=""
DETECTED_DISTRO_ID=""
DETECTED_DISTRO_LIKE=""
PRESENT_TOOLS=()
MISSING_TOOLS=()
PACMAN_PACKAGES_TO_INSTALL=()
AUR_PACKAGES_TO_INSTALL=()

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-host-tools.sh [--check | --install]

Checks whether required host tools are available for this repository.

Modes:
  --check    Check tools and print placeholders for missing installs (default)
  --install  Install only missing tools via pacman and paru/yay

Notes:
  - Only Arch-based distributions are supported right now.
  - git and bash are assumed to already be installed.
  - Missing pacman packages are installed in one command.
  - Missing AUR packages are installed in one command.
EOF
}

log_info() {
  printf 'INFO: %s\n' "$*"
}

log_warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        MODE="check"
        ;;
      --install)
        MODE="install"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

detect_distro() {
  local os_release_path="/etc/os-release"

  [[ -r "$os_release_path" ]] || die "Cannot read $os_release_path"

  # shellcheck disable=SC1090
  . "$os_release_path"

  [[ -n "${ID:-}" ]] || die "Could not determine distro ID from $os_release_path"

  DETECTED_DISTRO_ID="$ID"
  DETECTED_DISTRO_LIKE="${ID_LIKE:-}"
}

ensure_supported_distro() {
  local token

  detect_distro

  for token in "${SUPPORTED_DISTRO_TOKENS[@]}"; do
    if [[ "$DETECTED_DISTRO_ID" == "$token" ]]; then
      return
    fi

    if [[ " $DETECTED_DISTRO_LIKE " == *" $token "* ]]; then
      return
    fi
  done

  die "Unsupported distro '$DETECTED_DISTRO_ID'. Only Arch-based distributions are supported right now."
}

detect_aur_helper() {
  if command_exists paru; then
    AUR_HELPER="paru"
    return
  fi

  if command_exists yay; then
    AUR_HELPER="yay"
    return
  fi

  die "Neither paru nor yay is installed. Install one AUR helper before continuing."
}

check_required_tools() {
  local tool

  PRESENT_TOOLS=()
  MISSING_TOOLS=()

  for tool in "${REQUIRED_TOOLS[@]}"; do
    if command_exists "$tool"; then
      PRESENT_TOOLS+=("$tool")
    else
      MISSING_TOOLS+=("$tool")
    fi
  done
}

append_unique() {
  local array_name="$1"
  local value="$2"
  local existing
  local -n target_array="$array_name"

  for existing in "${target_array[@]}"; do
    if [[ "$existing" == "$value" ]]; then
      return
    fi
  done

  target_array+=("$value")
}

prepare_package_plan() {
  local tool="$1"

  case "$tool" in
    pre-commit)
      append_unique PACMAN_PACKAGES_TO_INSTALL pre-commit
      ;;
    python3)
      append_unique PACMAN_PACKAGES_TO_INSTALL python
      append_unique PACMAN_PACKAGES_TO_INSTALL python-pip
      ;;
    rg)
      append_unique PACMAN_PACKAGES_TO_INSTALL ripgrep
      ;;
    sops)
      append_unique PACMAN_PACKAGES_TO_INSTALL sops
      ;;
    terraform)
      append_unique PACMAN_PACKAGES_TO_INSTALL terraform
      ;;
    packer)
      append_unique PACMAN_PACKAGES_TO_INSTALL packer
      ;;
    ansible-playbook)
      append_unique PACMAN_PACKAGES_TO_INSTALL ansible
      ;;
    ansible-lint)
      append_unique PACMAN_PACKAGES_TO_INSTALL ansible-lint
      ;;
    kubectl)
      append_unique PACMAN_PACKAGES_TO_INSTALL kubectl
      ;;
    flux)
      append_unique PACMAN_PACKAGES_TO_INSTALL fluxcd
      ;;
    bws)
      append_unique AUR_PACKAGES_TO_INSTALL bws-bin
      ;;
    jq)
      append_unique PACMAN_PACKAGES_TO_INSTALL jq
      ;;
    yq)
      append_unique PACMAN_PACKAGES_TO_INSTALL yq
      ;;
    *)
      die "No package mapping defined for tool: $tool"
      ;;
  esac
}

build_install_plan() {
  local tool

  PACMAN_PACKAGES_TO_INSTALL=()
  AUR_PACKAGES_TO_INSTALL=()

  for tool in "${MISSING_TOOLS[@]}"; do
    prepare_package_plan "$tool"
  done
}

print_tool_report() {
  local tool

  log_info "Present tools (${#PRESENT_TOOLS[@]}):"
  for tool in "${PRESENT_TOOLS[@]}"; do
    printf '  - %s\n' "$tool"
  done

  if [[ ${#MISSING_TOOLS[@]} -eq 0 ]]; then
    return
  fi

  log_warn "Missing required tools (${#MISSING_TOOLS[@]}):"
  for tool in "${MISSING_TOOLS[@]}"; do
    printf '  - %s\n' "$tool" >&2
  done
}

print_install_plan() {
  cat >&2 <<EOF
Detected distro: $DETECTED_DISTRO_ID
Install plan for missing tools:
EOF

  if [[ ${#PACMAN_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
    printf '  sudo pacman -S --needed' >&2
    printf ' %q' "${PACMAN_PACKAGES_TO_INSTALL[@]}" >&2
    printf '\n' >&2
  else
    printf '  No pacman packages need installation.\n' >&2
  fi

  if [[ ${#AUR_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
    if [[ -n "$AUR_HELPER" ]]; then
      printf '  %s -S --needed' "$AUR_HELPER" >&2
    else
      printf '  <paru-or-yay> -S --needed' >&2
    fi
    printf ' %q' "${AUR_PACKAGES_TO_INSTALL[@]}" >&2
    printf '\n' >&2
  else
    printf '  No AUR packages need installation.\n' >&2
  fi
}

install_missing_tools() {
  if [[ ${#AUR_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
    detect_aur_helper
  fi

  if [[ ${#PACMAN_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
    log_info "Installing missing pacman packages"
    sudo pacman -S --needed "${PACMAN_PACKAGES_TO_INSTALL[@]}"
  fi

  if [[ ${#AUR_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
    log_info "Installing missing AUR packages with $AUR_HELPER"
    "$AUR_HELPER" -S --needed "${AUR_PACKAGES_TO_INSTALL[@]}"
  fi
}

initialize_pre_commit_hooks() {
  log_info "Initializing pre-commit hooks from repo root"
  (
    cd "$REPO_ROOT"
    pre-commit install
  )
}

main() {
  parse_args "$@"
  ensure_supported_distro
  check_required_tools
  print_tool_report

  if [[ ${#MISSING_TOOLS[@]} -eq 0 ]]; then
    if [[ "$MODE" == "install" ]]; then
      initialize_pre_commit_hooks
    fi

    log_info "All required host tools are already installed."
    exit 0
  fi

  build_install_plan

  if [[ "$MODE" == "install" ]]; then
    install_missing_tools
    check_required_tools
    print_tool_report

    if [[ ${#MISSING_TOOLS[@]} -eq 0 ]]; then
      initialize_pre_commit_hooks
      log_info "All required host tools are now installed."
      exit 0
    fi

    die "Some required tools are still missing after installation."
  fi

  if [[ ${#AUR_PACKAGES_TO_INSTALL[@]} -gt 0 ]] && { command_exists paru || command_exists yay; }; then
    detect_aur_helper
  fi

  print_install_plan
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
