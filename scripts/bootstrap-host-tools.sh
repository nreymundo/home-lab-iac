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
  helm
  helm-diff
  helm-secrets
  flux
  ansible-playbook
  bws
  jq
  yq
  kubeconform
  trivy
  checkov
)

readonly ARCH_DISTRO_TOKENS=(
  arch
  archlinux
)

readonly UBUNTU_DISTRO_TOKENS=(
  ubuntu
)

readonly HELM_DIFF_PLUGIN_URL="https://github.com/databus23/helm-diff"
readonly HELM_SECRETS_PLUGIN_VERSION="4.7.7"
readonly HELM_SECRETS_RELEASE_BASE_URL="https://github.com/jkroepke/helm-secrets/releases/download/v$HELM_SECRETS_PLUGIN_VERSION"
readonly HELM_SECRETS_CLI_PLUGIN_URL="$HELM_SECRETS_RELEASE_BASE_URL/secrets-$HELM_SECRETS_PLUGIN_VERSION.tgz"
readonly HELM_SECRETS_GETTER_PLUGIN_URL="$HELM_SECRETS_RELEASE_BASE_URL/secrets-getter-$HELM_SECRETS_PLUGIN_VERSION.tgz"
readonly HELM_SECRETS_POST_RENDERER_PLUGIN_URL="$HELM_SECRETS_RELEASE_BASE_URL/secrets-post-renderer-$HELM_SECRETS_PLUGIN_VERSION.tgz"
readonly ARCH_HELM_DIFF_PLUGIN_PATH="/usr/lib/helm/plugins/diff"
readonly ARCH_HELM_SECRETS_CLI_PLUGIN_PATH="/usr/lib/helm/plugins/secrets-cli"
readonly ARCH_HELM_SECRETS_GETTER_PLUGIN_PATH="/usr/lib/helm/plugins/secrets-getter"
readonly ARCH_HELM_SECRETS_POST_RENDERER_PLUGIN_PATH="/usr/lib/helm/plugins/secrets-post-renderer"

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
HELM_PLUGINS_TO_INSTALL=()
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

pacman_package_installed() {
  local package="$1"

  command_exists pacman || return 1
  pacman -Q "$package" >/dev/null 2>&1
}

helm_plugin_command_exists() {
  local plugin_command="$1"

  command_exists helm || return 1
  helm "$plugin_command" --help >/dev/null 2>&1
}

helm_plugin_metadata_exists() {
  local plugin_name="$1"
  local plugin_yaml
  local plugins_dir
  local line
  local name_pattern

  command_exists helm || return 1

  plugins_dir="$(helm env HELM_PLUGINS 2>/dev/null)" || return 1
  name_pattern="^[[:space:]]*name:[[:space:]]*\"?$plugin_name\"?[[:space:]]*$"

  for plugin_yaml in "$plugins_dir"/*/plugin.yaml; do
    [[ -f "$plugin_yaml" ]] || continue

    while IFS= read -r line; do
      if [[ "$line" =~ $name_pattern ]]; then
        return 0
      fi
    done < "$plugin_yaml"
  done

  return 1
}

tool_exists() {
  local tool="$1"

  case "$tool" in
    helm-diff)
      helm_plugin_command_exists diff
      ;;
    helm-secrets)
      helm_plugin_command_exists secrets && \
        helm_plugin_metadata_exists secrets-getter && \
        helm_plugin_metadata_exists secrets-post-renderer
      ;;
    *)
      command_exists "$tool"
      ;;
  esac
}

helm_plugin_spec_installed() {
  local plugin_name="$1"

  case "$plugin_name" in
    diff|secrets)
      helm_plugin_command_exists "$plugin_name"
      ;;
    *)
      helm_plugin_metadata_exists "$plugin_name"
      ;;
  esac
}

helm_plugin_source_is_local_path() {
  local plugin_source="$1"

  [[ "$plugin_source" == /* ]]
}

print_helm_plugin_install_command() {
  local plugin_source="$1"

  if helm_plugin_source_is_local_path "$plugin_source"; then
    # shellcheck disable=SC2016
    printf '  mkdir -p "$(helm env HELM_PLUGINS)" && ln -s %q "$(helm env HELM_PLUGINS)/%s"\n' \
      "$plugin_source" "${plugin_source##*/}" >&2
    return
  fi

  printf '  helm plugin install %q\n' "$plugin_source" >&2
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
    if tool_exists "$tool"; then
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
    helm)
      append_unique PACMAN_PACKAGES_TO_INSTALL helm
      ;;
    helm-diff)
      if ! pacman_package_installed helm-diff; then
        append_unique AUR_PACKAGES_TO_INSTALL helm-diff
      fi
      append_unique HELM_PLUGINS_TO_INSTALL "diff=$ARCH_HELM_DIFF_PLUGIN_PATH"
      ;;
    helm-secrets)
      if ! pacman_package_installed helm-secrets; then
        append_unique AUR_PACKAGES_TO_INSTALL helm-secrets
      fi
      append_unique HELM_PLUGINS_TO_INSTALL "secrets=$ARCH_HELM_SECRETS_CLI_PLUGIN_PATH"
      append_unique HELM_PLUGINS_TO_INSTALL "secrets-getter=$ARCH_HELM_SECRETS_GETTER_PLUGIN_PATH"
      append_unique HELM_PLUGINS_TO_INSTALL "secrets-post-renderer=$ARCH_HELM_SECRETS_POST_RENDERER_PLUGIN_PATH"
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
    kubeconform)
      append_unique PACMAN_PACKAGES_TO_INSTALL kubeconform
      ;;
    trivy)
      append_unique PACMAN_PACKAGES_TO_INSTALL trivy
      ;;
    checkov)
      append_unique MANUAL_TOOLS_TO_INSTALL checkov
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
    kubeconform)
      append_unique BREW_PACKAGES_TO_INSTALL kubeconform
      ;;
    trivy)
      append_unique BREW_PACKAGES_TO_INSTALL trivy
      ;;
    checkov)
      append_unique BREW_PACKAGES_TO_INSTALL checkov
      ;;
    sops)
      append_unique BREW_PACKAGES_TO_INSTALL sops
      ;;
    kubectl)
      append_unique BREW_PACKAGES_TO_INSTALL kubernetes-cli
      ;;
    helm)
      append_unique BREW_PACKAGES_TO_INSTALL helm
      ;;
    helm-diff)
      append_unique HELM_PLUGINS_TO_INSTALL "diff=$HELM_DIFF_PLUGIN_URL"
      ;;
    helm-secrets)
      append_unique HELM_PLUGINS_TO_INSTALL "secrets=$HELM_SECRETS_CLI_PLUGIN_URL"
      append_unique HELM_PLUGINS_TO_INSTALL "secrets-getter=$HELM_SECRETS_GETTER_PLUGIN_URL"
      append_unique HELM_PLUGINS_TO_INSTALL "secrets-post-renderer=$HELM_SECRETS_POST_RENDERER_PLUGIN_URL"
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
  HELM_PLUGINS_TO_INSTALL=()
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
    checkov)
      printf '    - checkov: install with `pipx install checkov`, or another isolated Python package method that puts `checkov` on PATH.\n' >&2
      ;;
    *)
      printf '    - %s: install manually.\n' "$tool" >&2
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

  log_warn "Missing or unavailable required tools (${#MISSING_TOOLS[@]}):"
  for tool in "${MISSING_TOOLS[@]}"; do
    printf '  - %s\n' "$tool" >&2
  done
}

print_install_plan() {
  local plugin_spec
  local plugin_url
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

      if [[ ${#HELM_PLUGINS_TO_INSTALL[@]} -gt 0 ]]; then
        for plugin_spec in "${HELM_PLUGINS_TO_INSTALL[@]}"; do
          plugin_url="${plugin_spec#*=}"
          print_helm_plugin_install_command "$plugin_url"
        done
      else
        printf '  No Helm plugins need registration.\n' >&2
      fi

      if [[ ${#MANUAL_TOOLS_TO_INSTALL[@]} -gt 0 ]]; then
        printf '  Manual installation still required for:\n' >&2
        for tool in "${MANUAL_TOOLS_TO_INSTALL[@]}"; do
          print_manual_install_hint "$tool"
        done
      else
        printf '  No manual installs are required.\n' >&2
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

      if [[ ${#HELM_PLUGINS_TO_INSTALL[@]} -gt 0 ]]; then
        for plugin_spec in "${HELM_PLUGINS_TO_INSTALL[@]}"; do
          plugin_url="${plugin_spec#*=}"
          print_helm_plugin_install_command "$plugin_url"
        done
      else
        printf '  No Helm plugins need installation.\n' >&2
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

install_helm_plugins() {
  local plugin_destination
  local plugin_name
  local plugin_spec
  local plugin_url
  local plugins_dir

  if [[ ${#HELM_PLUGINS_TO_INSTALL[@]} -eq 0 ]]; then
    return
  fi

  command_exists helm || die "helm is required to install Helm plugins. Install helm and rerun the script."

  for plugin_spec in "${HELM_PLUGINS_TO_INSTALL[@]}"; do
    plugin_name="${plugin_spec%%=*}"
    plugin_url="${plugin_spec#*=}"

    if helm_plugin_spec_installed "$plugin_name"; then
      continue
    fi

    if helm_plugin_source_is_local_path "$plugin_url"; then
      [[ -d "$plugin_url" ]] || die "Helm plugin source does not exist: $plugin_url"

      plugins_dir="$(helm env HELM_PLUGINS 2>/dev/null)" || die "Could not determine Helm plugin directory."
      plugin_destination="$plugins_dir/${plugin_url##*/}"

      mkdir -p "$plugins_dir"

      if [[ -e "$plugin_destination" || -L "$plugin_destination" ]]; then
        die "Helm plugin destination exists but $plugin_name is unavailable: $plugin_destination. Remove or fix it and rerun the script."
      fi

      log_info "Registering Helm plugin $plugin_name from $plugin_url"
      ln -s "$plugin_url" "$plugin_destination"
      continue
    fi

    log_info "Installing Helm plugin $plugin_name"
    helm plugin install "$plugin_url"
  done
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

      install_helm_plugins

      if [[ ${#MANUAL_TOOLS_TO_INSTALL[@]} -gt 0 ]]; then
        print_install_plan
        die "Some required tools still need manual installation on Arch. Install them and rerun the script."
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

      install_helm_plugins

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
