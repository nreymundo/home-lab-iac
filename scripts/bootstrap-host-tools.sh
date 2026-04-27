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

readonly ARCH_DISTRO_TOKENS=(
  arch
  archlinux
)

readonly UBUNTU_DISTRO_TOKENS=(
  ubuntu
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_ROOT

MODE="check"
AUR_HELPER=""
DETECTED_DISTRO_ID=""
DETECTED_DISTRO_LIKE=""
DISTRO_FAMILY=""
PRESENT_TOOLS=()
MISSING_TOOLS=()
PACMAN_PACKAGES_TO_INSTALL=()
AUR_PACKAGES_TO_INSTALL=()
APT_PACKAGES_TO_INSTALL=()
BREW_PACKAGES_TO_INSTALL=()
SNAP_CLASSIC_PACKAGES_TO_INSTALL=()
MANUAL_TOOLS_TO_INSTALL=()

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-host-tools.sh [--check | --install]

Checks whether required host tools are available for this repository.

Modes:
  --check    Check tools and print placeholders for missing installs (default)
  --install  Install only missing tools via the distro package manager

Notes:
  - Supported distributions: Arch-based and Ubuntu.
  - git and bash are assumed to already be installed.
  - Missing package-manager-backed packages are installed in one command when possible.
  - Ubuntu may use apt, Homebrew, and snap before falling back to manual steps.
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

  for token in "${ARCH_DISTRO_TOKENS[@]}"; do
    if [[ "$DETECTED_DISTRO_ID" == "$token" ]]; then
      DISTRO_FAMILY="arch"
      return
    fi

    if [[ " $DETECTED_DISTRO_LIKE " == *" $token "* ]]; then
      DISTRO_FAMILY="arch"
      return
    fi
  done

  for token in "${UBUNTU_DISTRO_TOKENS[@]}"; do
    if [[ "$DETECTED_DISTRO_ID" == "$token" ]]; then
      DISTRO_FAMILY="ubuntu"
      return
    fi

    if [[ " $DETECTED_DISTRO_LIKE " == *" $token "* ]]; then
      DISTRO_FAMILY="ubuntu"
      return
    fi
  done

  die "Unsupported distro '$DETECTED_DISTRO_ID'. Supported distros are Arch-based and Ubuntu."
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

prepare_arch_package_plan() {
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

prepare_ubuntu_package_plan() {
  local tool="$1"

  case "$tool" in
    pre-commit)
      append_unique APT_PACKAGES_TO_INSTALL pre-commit
      ;;
    python3)
      append_unique APT_PACKAGES_TO_INSTALL python3
      ;;
    rg)
      append_unique APT_PACKAGES_TO_INSTALL ripgrep
      ;;
    ansible-playbook)
      append_unique APT_PACKAGES_TO_INSTALL ansible
      ;;
    ansible-lint)
      append_unique APT_PACKAGES_TO_INSTALL ansible-lint
      ;;
    jq)
      append_unique APT_PACKAGES_TO_INSTALL jq
      ;;
    yq)
      append_unique APT_PACKAGES_TO_INSTALL yq
      ;;
    sops)
      append_unique BREW_PACKAGES_TO_INSTALL sops
      ;;
    kubectl)
      append_unique BREW_PACKAGES_TO_INSTALL kubernetes-cli
      ;;
    flux)
      append_unique BREW_PACKAGES_TO_INSTALL fluxcd/tap/flux
      ;;
    terraform)
      append_unique SNAP_CLASSIC_PACKAGES_TO_INSTALL terraform
      ;;
    packer|bws)
      append_unique MANUAL_TOOLS_TO_INSTALL "$tool"
      ;;
    *)
      die "No Ubuntu package mapping defined for tool: $tool"
      ;;
  esac
}

prepare_package_plan() {
  local tool="$1"

  case "$DISTRO_FAMILY" in
    arch)
      prepare_arch_package_plan "$tool"
      ;;
    ubuntu)
      prepare_ubuntu_package_plan "$tool"
      ;;
    *)
      die "Unsupported distro family '$DISTRO_FAMILY'"
      ;;
  esac
}

build_install_plan() {
  local tool

  PACMAN_PACKAGES_TO_INSTALL=()
  AUR_PACKAGES_TO_INSTALL=()
  APT_PACKAGES_TO_INSTALL=()
  BREW_PACKAGES_TO_INSTALL=()
  SNAP_CLASSIC_PACKAGES_TO_INSTALL=()
  MANUAL_TOOLS_TO_INSTALL=()

  for tool in "${MISSING_TOOLS[@]}"; do
    prepare_package_plan "$tool"
  done
}

print_manual_install_hint() {
  local tool="$1"

  case "$tool" in
    packer)
      printf '    - packer: install manually from the HashiCorp package repository or release artifact.\n' >&2
      ;;
    bws)
      printf '    - bws: install the Bitwarden Secrets Manager CLI from the vendor-provided binary or package.\n' >&2
      ;;
    *)
      printf '    - %s: install manually for Ubuntu.\n' "$tool" >&2
      ;;
  esac
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
  local tool

  cat >&2 <<EOF
Detected distro: $DETECTED_DISTRO_ID
Install plan for missing tools:
EOF

  case "$DISTRO_FAMILY" in
    arch)
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
      ;;
    ubuntu)
      if [[ ${#APT_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
        printf '  sudo apt-get update && sudo apt-get install -y' >&2
        printf ' %q' "${APT_PACKAGES_TO_INSTALL[@]}" >&2
        printf '\n' >&2
      else
        printf '  No apt packages need installation.\n' >&2
      fi

      if [[ ${#BREW_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
        printf '  brew install' >&2
        printf ' %q' "${BREW_PACKAGES_TO_INSTALL[@]}" >&2
        printf '\n' >&2
      else
        printf '  No Homebrew packages need installation.\n' >&2
      fi

      if [[ ${#SNAP_CLASSIC_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
        printf '  sudo snap install --classic' >&2
        printf ' %q' "${SNAP_CLASSIC_PACKAGES_TO_INSTALL[@]}" >&2
        printf '\n' >&2
      else
        printf '  No snap packages need installation.\n' >&2
      fi

      if [[ ${#MANUAL_TOOLS_TO_INSTALL[@]} -gt 0 ]]; then
        printf '  Manual installation still required for:\n' >&2
        for tool in "${MANUAL_TOOLS_TO_INSTALL[@]}"; do
          print_manual_install_hint "$tool"
        done
      else
        printf '  No manual Ubuntu installs are required.\n' >&2
      fi
      ;;
    *)
      die "Unsupported distro family '$DISTRO_FAMILY'"
      ;;
  esac
}

install_missing_tools() {
  case "$DISTRO_FAMILY" in
    arch)
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
      ;;
    ubuntu)
      if [[ ${#APT_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
        log_info "Installing missing apt packages"
        sudo apt-get update
        sudo apt-get install -y "${APT_PACKAGES_TO_INSTALL[@]}"
      fi

      if [[ ${#BREW_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
        command_exists brew || die "Homebrew is required to install some Ubuntu tools. Install brew and rerun the script."
        log_info "Installing missing Homebrew packages"
        brew install "${BREW_PACKAGES_TO_INSTALL[@]}"
      fi

      if [[ ${#SNAP_CLASSIC_PACKAGES_TO_INSTALL[@]} -gt 0 ]]; then
        command_exists snap || die "snap is required to install some Ubuntu tools. Install snapd and rerun the script."
        log_info "Installing missing snap packages"
        sudo snap install --classic "${SNAP_CLASSIC_PACKAGES_TO_INSTALL[@]}"
      fi

      if [[ ${#MANUAL_TOOLS_TO_INSTALL[@]} -gt 0 ]]; then
        print_install_plan
        die "Some required tools still need manual installation on Ubuntu. Install them and rerun the script."
      fi
      ;;
    *)
      die "Unsupported distro family '$DISTRO_FAMILY'"
      ;;
  esac
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

  if [[ "$DISTRO_FAMILY" == "arch" ]] && [[ ${#AUR_PACKAGES_TO_INSTALL[@]} -gt 0 ]] && { command_exists paru || command_exists yay; }; then
    detect_aur_helper
  fi

  print_install_plan
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
