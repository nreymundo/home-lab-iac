#!/usr/bin/env bash
# Run periodically from a host with cluster credentials and access to Unraid.
# Dry-run by default. UNRAID_NFS_HOST overrides the inline NFS server to match.
# Recover explicit stale handles and known mount-content mismatches.
set -euo pipefail
export LC_ALL=C

case "${1:-}:$#" in
  :0|--apply:1) ;;
  --help:1|-h:1) echo "Usage: $0 [--apply]"; exit 0 ;;
  *) echo "Usage: $0 [--apply]" >&2; exit 2 ;;
esac

host=${UNRAID_NFS_HOST:-192.168.10.4}
apply=${1:-}
kube() { timeout 12s kubectl --request-timeout=10s "$@"; }
nfs_online() { timeout 3s bash -c 'exec 3<>"/dev/tcp/$1/2049"' _ "$host" 2>/dev/null; }
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }

if ! nfs_online; then
  log "NFS at $host is unreachable; skipping recovery"
  exit 0
fi

# Resolve the real controller instead of guessing it from the pod name.
mounts=$({ kube get replicasets -A -o json && kube get pods -A -o json; } | jq -sr --arg host "$host" '
  (.[0].items | map({key: .metadata.uid, value: ([.metadata.ownerReferences[]? |
    select(.controller and .kind == "Deployment")][0])}) | from_entries) as $owners |
  .[1].items[] | select(.metadata.deletionTimestamp == null and .status.phase == "Running") | . as $pod |
  (.metadata.ownerReferences[]? | select(.controller and .kind == "ReplicaSet") | $owners[.uid] // empty) as $owner |
  .spec.containers[] | . as $container |
  select(any($pod.status.containerStatuses[]?; .name == $container.name and .state.running != null)) |
  .volumeMounts[]? | . as $mount |
  select(any($pod.spec.volumes[]?; .name == $mount.name and .nfs.server == $host)) |
  [$pod.metadata.namespace, $owner.name, $owner.uid, $pod.metadata.name, $container.name, .mountPath] | @tsv')

declare -A stale=() acted=()
failed=0
while IFS=$'\t' read -r ns deployment uid pod container path; do
  [[ -n "$pod" ]] || continue
  probe=(ls "$path")
  # A readable NFS subPath can resolve to the wrong directory after a reboot.
  if [[ "$ns/$deployment:$path" == immich/immich-server:/data ]]; then
    probe=(ls -d /data/library/ /data/thumbs/)
  fi
  if output=$(kube -n "$ns" exec "$pod" -c "$container" -- "${probe[@]}" 2>&1 >/dev/null); then
    continue
  fi
  if [[ "${output,,}" == *'stale file handle'* || "$output" == *StaleNetworkFileHandle* ]]; then
    stale[$ns/$deployment]=$uid
    log "Stale NFS mount: $ns/$pod ($container:$path)"
  elif [[ "$ns/$deployment:$path" == immich/immich-server:/data &&
          "$output" == *'No such file or directory'* &&
          ( "$output" == *'/data/library/'* || "$output" == *'/data/thumbs/'* ) ]]; then
    stale[$ns/$deployment]=$uid
    log "Immich NFS mount is missing expected photo directories: $ns/$pod ($container:$path)"
  else
    log "Inconclusive probe: $ns/$pod ($container:$path): ${output:-timed out}"
    failed=1
  fi
done <<< "$mounts"

for key in "${!stale[@]}"; do
  ns=${key%/*}
  deployment=${key#*/}
  resource=$(kube -n "$ns" get deployment "$deployment" -o json)
  # Do not interrupt a rollout or repeatedly restart an unresolved mount.
  if ! jq -e --arg uid "${stale[$key]}" '
    (.spec.replicas // 1) as $desired |
    .metadata.uid == $uid and .metadata.deletionTimestamp == null and (.spec.paused != true) and
    $desired > 0 and .metadata.generation == .status.observedGeneration and
    .status.updatedReplicas == $desired and .status.replicas == $desired and
    ((.spec.template.metadata.annotations["kubectl.kubernetes.io/restartedAt"] // "1970-01-01T00:00:00Z") |
      sub("[+-]00:00$"; "Z") | fromdateiso8601 < (now - 900))' <<< "$resource" >/dev/null; then
    log "Skipping $key: rollout in progress, recent restart, or deployment changed"
    failed=1
    continue
  fi
  if [[ "$apply" != --apply ]]; then
    log "Would restart $key"
    continue
  fi
  if ! nfs_online; then
    log "NFS became unreachable; stopping further restarts"
    failed=1
    break
  fi
  if kube -n "$ns" rollout restart "deployment/$deployment"; then
    acted[$key]=1
  else
    failed=1
  fi
done

for key in "${!acted[@]}"; do
  if ! timeout 95s kubectl -n "${key%/*}" rollout status "deployment/${key#*/}" --timeout=90s; then
    failed=1
  fi
done
exit "$failed"
