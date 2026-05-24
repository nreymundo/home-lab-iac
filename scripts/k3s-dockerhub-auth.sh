#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="${SCRIPT_PATH%/*}"
if [[ "$SCRIPT_DIR" == "$SCRIPT_PATH" ]]; then
  SCRIPT_DIR="."
fi
SCRIPT_DIR="$(cd -- "$SCRIPT_DIR" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
INVENTORY_FILE="${INVENTORY_FILE:-${REPO_ROOT}/ansible/inventories/k3s-nodes.yml}"
SSH_USER="${SSH_USER:-}"
KUBECTL="${KUBECTL:-kubectl}"
SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
)

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

load_nodes() {
  if [[ ! -r "$INVENTORY_FILE" ]]; then
    printf 'Inventory file not readable: %s\n' "$INVENTORY_FILE" >&2
    exit 1
  fi

  mapfile -t NODES < <(
    awk '
      /^    k3s_nodes:/ { in_group = 1; next }
      in_group && /^      hosts:/ { in_hosts = 1; next }
      in_hosts && /^        [A-Za-z0-9_.-]+:/ {
        if (node && host) print node, host, user, port
        node = $1
        sub(/:$/, "", node)
        host = ""
        user = ""
        port = ""
        next
      }
      in_hosts && /^          ansible_host:/ {
        host = $2
        gsub(/"/, "", host)
        next
      }
      in_hosts && /^          ansible_user:/ {
        user = $2
        gsub(/"/, "", user)
        next
      }
      in_hosts && /^          ansible_port:/ {
        port = $2
        gsub(/"/, "", port)
        next
      }
      END {
        if (node && host) print node, host, user, port
      }
    ' "$INVENTORY_FILE"
  )

  if [[ "${#NODES[@]}" -eq 0 ]]; then
    printf 'No k3s_nodes hosts found in inventory: %s\n' "$INVENTORY_FILE" >&2
    exit 1
  fi
}

write_registries_config() {
  local ip="$1"
  local user="$2"
  local port="$3"

  ssh "${SSH_OPTS[@]}" -p "$port" "${user}@${ip}" \
    'sudo install -d -m 0755 /etc/rancher/k3s && sudo tee /etc/rancher/k3s/registries.yaml >/dev/null && sudo chmod 0600 /etc/rancher/k3s/registries.yaml' <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://registry-1.docker.io"

configs:
  "registry-1.docker.io":
    auth:
      username: "${DOCKERHUB_USER}"
      # Docker Hub access tokens are supplied through the registry password field.
      password: "${DOCKERHUB_TOKEN}"
EOF
}

restart_node() {
  local node="$1"
  local ip="$2"
  local inventory_user="$3"
  local port="$4"
  local user="${SSH_USER:-$inventory_user}"

  if [[ -z "$user" ]]; then
    printf 'No SSH user for %s; set ansible_user in %s or export SSH_USER.\n' "$node" "$INVENTORY_FILE" >&2
    exit 1
  fi

  if [[ -z "$port" ]]; then
    port="22"
  fi

  printf '\n==> Cordoning %s\n' "$node"
  "$KUBECTL" cordon "$node"

  printf '==> Writing Docker Hub auth to %s (%s@%s:%s)\n' "$node" "$user" "$ip" "$port"
  write_registries_config "$ip" "$user" "$port"

  printf '==> Restarting k3s on %s\n' "$node"
  ssh "${SSH_OPTS[@]}" -p "$port" "${user}@${ip}" 'sudo systemctl restart k3s'

  printf '==> Waiting for %s to become Ready\n' "$node"
  "$KUBECTL" wait "node/${node}" --for=condition=Ready --timeout=10m

  printf '==> Uncordoning %s\n' "$node"
  "$KUBECTL" uncordon "$node"
}

retry_image_pull_pods() {
  printf '\n==> Retrying pods stuck on image pulls\n'

  local pods
  pods=$("$KUBECTL" get pods -A --no-headers | awk '$4 ~ /ImagePullBackOff|ErrImagePull/ { print $1, $2 }')

  if [[ -z "$pods" ]]; then
    printf 'No ImagePullBackOff or ErrImagePull pods found.\n'
    return
  fi

  while read -r namespace pod; do
    [[ -z "${namespace:-}" || -z "${pod:-}" ]] && continue
    printf 'Deleting %s/%s\n' "$namespace" "$pod"
    "$KUBECTL" delete pod -n "$namespace" "$pod" --wait=false
  done <<<"$pods"
}

require_command ssh
require_command awk
require_command "$KUBECTL"
load_nodes

read -r -p 'Docker Hub username: ' DOCKERHUB_USER
read -r -s -p 'Docker Hub access token (not account password): ' DOCKERHUB_TOKEN
printf '\n'

if [[ -z "$DOCKERHUB_USER" || -z "$DOCKERHUB_TOKEN" ]]; then
  printf 'Docker Hub username and token are required.\n' >&2
  exit 1
fi

printf 'Using inventory: %s\n' "$INVENTORY_FILE"

for entry in "${NODES[@]}"; do
  read -r node ip inventory_user port <<<"$entry"
  restart_node "$node" "$ip" "$inventory_user" "$port"
done

retry_image_pull_pods

printf '\n==> Final node status\n'
"$KUBECTL" get nodes -o wide

printf '\n==> Remaining non-running pods\n'
"$KUBECTL" get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
