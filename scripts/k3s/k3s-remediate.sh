#!/usr/bin/env bash
# Allowlisted tier 0/1 auto-remediation for the k3s cluster, run on the
# Hermes host beside k3s-health-check.sh (detection stays there; this
# script only performs pre-approved rule classes):
#   Tier 0: delete Jobs whose Complete/Failed condition turned True more
#           than JOB_TTL_DAYS (7) ago, outside protected namespaces.
#   Tier 1: delete pods stuck in CrashLoopBackOff/ImagePullBackOff/
#           ErrImagePull owned by a Deployment (ReplicaSet) or DaemonSet,
#           older than POD_MIN_AGE_MIN (30) minutes, with no PVC volumes,
#           outside protected namespaces. Pod age is a proxy for
#           stuck-duration; the API exposes no waiting-since timestamp.
# Guard rails: at most MAX_ACTIONS_PER_RUN (5) deletions per run; one
# action per owner UID per OWNER_COOLDOWN_HOURS (24); tier-1 deletions
# stop entirely once BREAKER_KEYS (3) distinct pod owners were acted on
# in the last 24h (cluster event, not independent faults). Tier-0 job
# cleanup is routine hygiene and never trips the breaker.
# No notifications: the audit log is the record.
# Default is dry-run (log planned actions only); --apply executes.
# Exit 0 = ran (with or without actions), 1 = error, 2 = circuit breaker.
# Dependencies: bash 4+, kubectl, jq 1.6+, GNU date, timeout, awk.
# Numeric K3S_REM_* overrides: TIMEOUT=15, JOB_TTL_DAYS=7,
# POD_MIN_AGE_MIN=30, MAX_ACTIONS_PER_RUN=5, OWNER_COOLDOWN_HOURS=24,
# BREAKER_KEYS=3. String overrides: K3S_REM_PROTECTED_NS (default
# "kube-system longhorn-system flux-system cert-manager"), K3S_REM_STATE
# (default ~/.local/state/k3s-remediate).
# kubectl inherits the host's current context/KUBECONFIG; all calls have
# deadlines. jq programs deliberately use literal dollar signs.
# shellcheck disable=SC2016
set -uo pipefail
umask 077

APPLY=false
case "${1:-}" in
  --apply) APPLY=true ;;
  --help | -h)
    printf 'Usage: %s [--apply]\nSee the script header for rules and K3S_REM_* overrides.\n' "$0"
    exit 0
    ;;
  '') ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
esac
if (($# > 1)); then
  printf 'Expected at most one argument\n' >&2
  exit 2
fi

STATE=${K3S_REM_STATE:-$HOME/.local/state/k3s-remediate}
LOG=$STATE/actions.log
LEDGER=$STATE/ledger.tsv
PROTECTED=${K3S_REM_PROTECTED_NS:-"kube-system longhorn-system flux-system cert-manager"}
STAMP=$(date -u +%FT%TZ)
NOW=$(date +%s)
MODE=dry-run
if $APPLY; then MODE=apply; fi

for tool in kubectl jq date timeout awk; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    printf '%s [ERROR] Required host tool missing: %s\n' "$STAMP" "$tool" >&2
    exit 1
  fi
done
for setting in TIMEOUT=15 JOB_TTL_DAYS=7 POD_MIN_AGE_MIN=30 MAX_ACTIONS_PER_RUN=5 \
  OWNER_COOLDOWN_HOURS=24 BREAKER_KEYS=3; do
  name=${setting%%=*}
  default=${setting#*=}
  variable=K3S_REM_$name
  value=${!variable:-$default}
  if [[ ! "$value" =~ ^[0-9]+$ ]] || ((value < 1)); then
    printf '%s [ERROR] Invalid positive integer %s=%s\n' "$STAMP" "$variable" "$value" >&2
    exit 1
  fi
  printf -v "$name" '%s' "$value"
done

mkdir -p "$STATE" || exit 1
logf() { printf '%s %s\n' "$STAMP" "$*" >> "$LOG"; }
kube() { timeout "${TIMEOUT}s" kubectl --request-timeout="${TIMEOUT}s" "$@" 2> /dev/null; }

# Circuit breaker (tier 1 only): too many distinct pod owners acted on in
# the last 24h means a cluster event; stop mutating pods and log it.
breaker=$(awk -F'\t' -v cutoff=$((NOW - OWNER_COOLDOWN_HOURS * 3600)) \
  '$1 > cutoff && $3 == "delete-pod" { seen[$2] = 1 } END { n = 0; for (k in seen) n++; print n }' \
  "$LEDGER" 2> /dev/null) || breaker=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/k3s-remediate.XXXXXXXX") || exit 1
trap 'rm -rf -- "$WORK"' EXIT

if ! kube get nodes -o json > "$WORK/nodes" || ! jq -e '.items | type == "array"' "$WORK/nodes" > /dev/null; then
  logf "error api-unreachable mode=$MODE"
  exit 1
fi

# Tier 0 candidates: key<TAB>ns<TAB>name<TAB>age_days
if ! kube get jobs -A -o json > "$WORK/jobs"; then
  logf "error jobs-list-failed mode=$MODE"
  exit 1
fi
if ! jq -r --argjson now "$NOW" --argjson ttl "$((JOB_TTL_DAYS * 86400))" --arg prot "$PROTECTED" '
  .items[]
  | select(.metadata.deletionTimestamp == null)
  | select(.metadata.namespace as $ns | ($prot | split(" ") | index($ns) | not))
  | ([.status.conditions[]? | select(.status == "True" and (.type == "Complete" or .type == "Failed"))][0]) as $c
  | select($c != null)
  | ($c.lastTransitionTime // "") as $ts
  | select($ts != "")
  | ($now - ($ts | fromdateiso8601)) as $age
  | select($age > $ttl)
  | [.metadata.uid, .metadata.namespace, .metadata.name, ($age / 86400 | floor | tostring)]
  | @tsv' "$WORK/jobs" > "$WORK/tier0"; then
  logf "error tier0-parse mode=$MODE"
  exit 1
fi

# Tier 1 candidates: key<TAB>owner_kind<TAB>ns<TAB>name<TAB>age_min<TAB>reasons
if ! kube get pods -A -o json > "$WORK/pods"; then
  logf "error pods-list-failed mode=$MODE"
  exit 1
fi
if ! jq -r --argjson now "$NOW" --argjson minage "$((POD_MIN_AGE_MIN * 60))" --arg prot "$PROTECTED" \
  --argjson kinds '["ReplicaSet", "DaemonSet"]' \
  --argjson reasons '["CrashLoopBackOff", "ImagePullBackOff", "ErrImagePull"]' '
  .items[]
  | select(.metadata.deletionTimestamp == null)
  | select(.status.phase == "Running" or .status.phase == "Pending")
  | select(.metadata.namespace as $ns | ($prot | split(" ") | index($ns) | not))
  | select(any(.spec.volumes[]?; .persistentVolumeClaim != null) | not)
  | ([.metadata.ownerReferences[]? | select(.controller == true)][0]) as $owner
  | select($owner != null and ($kinds | index($owner.kind)))
  | ($now - (.metadata.creationTimestamp | fromdateiso8601)) as $age
  | select($age > $minage)
  | [(.status.containerStatuses[]?, .status.initContainerStatuses[]?)
    | .state.waiting.reason // empty | . as $reason | select($reasons | index($reason))] as $waiting
  | select($waiting | length > 0)
  | [$owner.uid, $owner.kind, .metadata.namespace, .metadata.name,
    (($age / 60) | floor | tostring), ($waiting | unique | join(","))]
  | @tsv' "$WORK/pods" > "$WORK/tier1"; then
  logf "error tier1-parse mode=$MODE"
  exit 1
fi

# Owner cooldown: skip candidates whose owner key was acted on recently,
# so a persistently broken object is deleted at most once per cooldown.
cooldown_active() {
  local key=$1 cutoff=$((NOW - OWNER_COOLDOWN_HOURS * 3600))
  awk -F'\t' -v key="$key" -v cutoff="$cutoff" \
    '$2 == key && $1 > cutoff { found = 1 } END { exit found ? 0 : 1 }' "$LEDGER" 2> /dev/null
}

acted=0
skipped=0
logf "run-start mode=$MODE t0_candidates=$(wc -l < "$WORK/tier0") t1_candidates=$(wc -l < "$WORK/tier1")"

while IFS=$'\t' read -r key ns name age; do
  [[ -n "$key" ]] || continue
  if cooldown_active "$key" || ((acted >= MAX_ACTIONS_PER_RUN)); then
    skipped=$((skipped + 1))
    continue
  fi
  if $APPLY; then
    if kube -n "$ns" delete job "$name" > /dev/null; then
      printf '%s\t%s\tdelete-job\t%s/%s\n' "$NOW" "$key" "$ns" "$name" >> "$LEDGER"
      logf "applied tier=0 action=delete-job object=$ns/$name age_days=$age"
      acted=$((acted + 1))
    else
      logf "error tier=0 action=delete-job object=$ns/$name delete-failed"
    fi
  else
    logf "dry-run tier=0 action=delete-job object=$ns/$name age_days=$age"
    acted=$((acted + 1))
  fi
done < "$WORK/tier0"

while IFS=$'\t' read -r key kind ns name age reasons; do
  [[ -n "$key" ]] || continue
  if ((breaker >= BREAKER_KEYS)); then
    break
  fi
  if cooldown_active "$key" || ((acted >= MAX_ACTIONS_PER_RUN)); then
    skipped=$((skipped + 1))
    continue
  fi
  if $APPLY; then
    if kube -n "$ns" delete pod "$name" > /dev/null; then
      printf '%s\t%s\tdelete-pod\t%s/%s\n' "$NOW" "$key" "$ns" "$name" >> "$LEDGER"
      logf "applied tier=1 action=delete-pod owner=$kind object=$ns/$name age_min=$age reasons=$reasons"
      acted=$((acted + 1))
      breaker=$((breaker + 1))
    else
      logf "error tier=1 action=delete-pod object=$ns/$name delete-failed"
    fi
  else
    logf "dry-run tier=1 action=delete-pod owner=$kind object=$ns/$name age_min=$age reasons=$reasons"
    acted=$((acted + 1))
  fi
done < "$WORK/tier1"

logf "run-end mode=$MODE actions=$acted skipped=$skipped"
if ((breaker >= BREAKER_KEYS)); then
  logf "circuit-breaker-open mode=$MODE pod_owners_acted_24h=$breaker"
  printf 'circuit-breaker-open pod_owners_acted_24h=%s\n' "$breaker"
  exit 2
fi
printf 'mode=%s actions=%s skipped=%s\n' "$MODE" "$acted" "$skipped"
exit 0
