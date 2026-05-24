#!/usr/bin/env bash
set -euo pipefail

if [[ "${BOOTSTRAP_ENABLED:-false}" != "true" ]]; then
  exit 0
fi

cluster_status="$(ssh -F /dev/null "${CLUSTER_SSH_HOST}" 'pvesh get /cluster/status --output-format json')"
node_ip="$({
  printf '%s\n' "${cluster_status}" \
    | jq -r --arg node "${TARGET_NODE}" '.[] | select(.type == "node" and .name == $node and .online == 1) | .ip' \
    | head -n 1
})"

if [[ -z "${node_ip}" || "${node_ip}" == "null" ]]; then
  printf 'Could not resolve online Proxmox node %q from cluster status\n' "${TARGET_NODE}" >&2
  exit 1
fi

if [[ -n "${PACKAGES}" ]]; then
  ssh -F /dev/null "${NODE_SSH_USER}@${node_ip}" \
    "pct exec ${VMID} -- ${PACKAGE_MANAGER} install -y ${PACKAGES}"
fi

if [[ -n "${SERVICES}" ]]; then
  ssh -F /dev/null "${NODE_SSH_USER}@${node_ip}" \
    "pct exec ${VMID} -- systemctl enable --now ${SERVICES}"
fi

if [[ "${WAIT_FOR_SSH}" == "true" ]]; then
  for _ in $(seq 1 "${TIMEOUT_ATTEMPTS}"); do
    if ssh \
      -F /dev/null \
      -o BatchMode=yes \
      -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout="${CONNECT_TIMEOUT}" \
      "${SSH_USER}@${IP_ADDRESS}" \
      true; then
      exit 0
    fi

    sleep "${RETRY_DELAY}"
  done

  printf 'SSH did not become reachable on %s\n' "${IP_ADDRESS}" >&2
  exit 1
fi
