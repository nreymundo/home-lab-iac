#!/usr/bin/env bash
set -euo pipefail

SSH_USER="${SSH_USER:-ubuntu}"
KUBECTL="${KUBECTL:-kubectl}"
SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
)

NODES=(
  "k3s-node-01 192.168.10.50"
  "k3s-node-02 192.168.10.51"
  "k3s-node-03 192.168.10.52"
)

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

write_registries_config() {
  local ip="$1"

  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" \
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

  printf '\n==> Cordoning %s\n' "$node"
  "$KUBECTL" cordon "$node"

  printf '==> Writing Docker Hub auth to %s\n' "$node"
  write_registries_config "$ip"

  printf '==> Restarting k3s on %s\n' "$node"
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" 'sudo systemctl restart k3s'

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

read -r -p 'Docker Hub username: ' DOCKERHUB_USER
read -r -s -p 'Docker Hub access token (not account password): ' DOCKERHUB_TOKEN
printf '\n'

if [[ -z "$DOCKERHUB_USER" || -z "$DOCKERHUB_TOKEN" ]]; then
  printf 'Docker Hub username and token are required.\n' >&2
  exit 1
fi

for entry in "${NODES[@]}"; do
  read -r node ip <<<"$entry"
  restart_node "$node" "$ip"
done

retry_image_pull_pods

printf '\n==> Final node status\n'
"$KUBECTL" get nodes -o wide

printf '\n==> Remaining non-running pods\n'
"$KUBECTL" get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
