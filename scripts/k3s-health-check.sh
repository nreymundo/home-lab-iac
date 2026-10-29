#!/usr/bin/env bash
# Read-only, host-run k3s checks. Dependencies: bash 4+, kubectl, jq 1.6+,
# curl, openssl, GNU date, timeout, base64, mktemp. No scheduling/notifications.
# Default: append findings only; --full also prints all observations. Exit 0/1/2
# means no WARN/CRIT, WARN, CRIT respectively (INFO signals do not raise exit).
# K3S_HEALTH_LOG defaults to ~/.local/state/k3s-health-check/health.log.
# Numeric K3S_HEALTH_* defaults (seconds unless the suffix says otherwise):
# TIMEOUT=15, FORWARD_WAIT=15, CERT_WARN_DAYS=30, CERT_CRIT_DAYS=14,
# CA_WARN_DAYS=365, CA_CRIT_DAYS=180, RESTART_WARN=3 (over RESTART_HOURS=24),
# STORM_CONTAINERS=10, STORM_NAMESPACES=2, STORM_HOURS=24,
# FS_WARN_PERCENT=80, FS_CRIT_PERCENT=90, MEM_WARN_PERCENT=85,
# MEM_CRIT_PERCENT=92, PVC_WARN_PERCENT=80, PVC_CRIT_PERCENT=90,
# AVAILABILITY_PERCENT=99.9, FAILURE_HOURS=24, RENEWAL_GRACE_HOURS=24,
# FLUX_INTERVAL_MULTIPLIER=2, EVENT_HOURS=6, EVENT_STORM_COUNT=10,
# TRAEFIK_REPLICAS=3, STREAM_SECONDS=180.
# String overrides: PROM_NAMESPACE=observability,
# PROM_SERVICE=observability-kube-prometh-prometheus. Uses a random loopback
# port owned by this invocation, never an existing listener. kubectl inherits
# the host's current context/KUBECONFIG. All external calls have deadlines.
# Cert gauges are remaining seconds, refreshed ~30m, not an exhaustive audit.
# Leaf renewal needs a k3s restart inside its 120d window; CAs do not auto-renew.
# jq programs deliberately use literal dollar signs; collectors run by name.
# shellcheck disable=SC2016,SC2329
set -uo pipefail
umask 077

FULL=false
case "${1:-}" in
  --full) FULL=true ;;
  --help | -h)
    printf 'Usage: %s [--full]\nSee the script header for K3S_HEALTH_* overrides.\n' "$0"
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
LOG=${K3S_HEALTH_LOG:-$HOME/.local/state/k3s-health-check/health.log}
NOW=$(date +%s)
STAMP=$(date -u +%FT%TZ)
PF_PID=''
WORK=''

finish() {
  local code=0 lines
  if [[ -s "$WORK/report" ]]; then
    if $FULL; then cat "$WORK/report"; fi
    lines=$(grep -E ' \[(CRIT|WARN|INFO)\] ' "$WORK/report" || true)
    if [[ -n "$lines" ]]; then
      if ! mkdir -p -- "$(dirname -- "$LOG")" || ! printf '%s\n' "$lines" >> "$LOG"; then
        printf '%s [CRIT] Cannot append findings to %s\n' "$STAMP" "$LOG" >&2
        code=2
      fi
    fi
    if grep -q ' \[CRIT\] ' "$WORK/report"; then
      code=2
    elif grep -q ' \[WARN\] ' "$WORK/report" && ((code < 1)); then code=1; fi
  fi
  return "$code"
}
cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" 2> /dev/null || true
    wait "$PF_PID" 2> /dev/null || true
  fi
  if [[ -n "$WORK" ]]; then rm -rf -- "$WORK"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
WORK=$(mktemp -d "${TMPDIR:-/tmp}/k3s-health.XXXXXXXX") || exit 2
: > "$WORK/report"
record() {
  local severity=$1 message=${2//$'\n'/ }
  message=${message//$'\r'/ }
  printf '%s [%s] %s\n' "$STAMP" "$severity" "$message" >> "$WORK/report"
}
unavailable() { record INFO "$* signal unavailable (N/A)"; }
for tool in kubectl jq curl openssl date timeout base64; do
  if ! command -v "$tool" > /dev/null 2>&1; then record CRIT "Required host tool missing: $tool"; fi
done
if grep -q ' \[CRIT\] ' "$WORK/report"; then
  finish
  exit $?
fi

# Keep numeric configuration out of jq source and reject malformed overrides.
for setting in TIMEOUT=15 FORWARD_WAIT=15 CERT_WARN_DAYS=30 CERT_CRIT_DAYS=14 \
  CA_WARN_DAYS=365 CA_CRIT_DAYS=180 RESTART_WARN=3 RESTART_HOURS=24 \
  STORM_CONTAINERS=10 STORM_NAMESPACES=2 STORM_HOURS=24 FS_WARN_PERCENT=80 \
  FS_CRIT_PERCENT=90 MEM_WARN_PERCENT=85 MEM_CRIT_PERCENT=92 PVC_WARN_PERCENT=80 \
  PVC_CRIT_PERCENT=90 AVAILABILITY_PERCENT=99.9 FAILURE_HOURS=24 \
  RENEWAL_GRACE_HOURS=24 FLUX_INTERVAL_MULTIPLIER=2 EVENT_HOURS=6 \
  EVENT_STORM_COUNT=10 TRAEFIK_REPLICAS=3 STREAM_SECONDS=180; do
  name=${setting%%=*}
  default=${setting#*=}
  variable=K3S_HEALTH_$name
  value=${!variable:-$default}
  if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! jq -en --argjson v "$value" '$v > 0' > /dev/null 2>&1; then
    record CRIT "Invalid positive numeric setting $variable"
  else
    printf -v "$name" '%s' "$value"
  fi
done
if grep -q ' \[CRIT\] ' "$WORK/report"; then
  finish
  exit $?
fi
kube() { timeout "${TIMEOUT}s" kubectl --request-timeout="${TIMEOUT}s" "$@" 2> /dev/null; }
get_json() {
  local file=$1
  shift
  kube get "$@" -o json > "$WORK/$file" && jq -e '.items | type == "array"' "$WORK/$file" > /dev/null
}
# jq collectors emit [severity, message] pairs; parse failure is not healthy.
rows() {
  local file=$1 program=$2
  shift 2
  if ! jq -r "$@" "$program | @tsv" "$file" > "$WORK/rows"; then return 1; fi
  local level message
  while IFS=$'\t' read -r level message; do
    [[ -z "$level" ]] || record "$level" "$message"
  done < "$WORK/rows"
}
run() {
  local collector=$1 rc
  record OK "--- $collector ---"
  (
    set -e
    "$collector"
  ) 2> "$WORK/collector-error"
  rc=$?
  if ((rc != 0)); then unavailable "$collector: collector failed"; fi
}

if ! get_json nodes nodes; then
  record CRIT 'Kubernetes API unreachable or node inventory denied/invalid'
  finish
  exit $?
fi
record OK 'Kubernetes API reachable'

nodes() {
  rows "$WORK/nodes" '
    .items[] | . as $n | ["OK", "node \(.metadata.name) version=\(.status.nodeInfo.kubeletVersion)"],
    ([.status.conditions[]? | select(.type=="Ready")][0] // {type:"Ready",status:"Missing"} |
      select(.status!="True") | ["CRIT", "node \($n.metadata.name) Ready=\(.status)"]),
    (.status.conditions[]? | select(.type|test("^(MemoryPressure|DiskPressure|PIDPressure)$")) |
      select(.status!="False") | ["WARN", "node \($n.metadata.name) \(.type)=\(.status)"])'
  rows "$WORK/nodes" '[.items[].status.nodeInfo.kubeletVersion] | unique |
    select(length>1) | ["WARN", "k3s version skew: \(join(", "))"]'
}
readyz() {
  local rc=0 line
  kube get --raw '/readyz?verbose' > "$WORK/readyz" || rc=$?
  while IFS= read -r line; do
    case "$line" in
      '[+]'*' ok') record OK "API readyz $line" ;;
      '[-]'*) record CRIT "API readyz $line" ;;
    esac
  done < "$WORK/readyz"
  if ((rc != 0)); then record CRIT 'API readyz failed (possible etcd/quorum/component failure)'; fi
  if [[ ! -s "$WORK/readyz" ]]; then unavailable 'API readyz component details'; fi
}
pods() {
  get_json pods pods -A
  rows "$WORK/pods" '.items[] | . as $p |
    (select(.status.phase | IN("Pending","Failed","Unknown")) |
      ["WARN", "pod \(.metadata.namespace)/\(.metadata.name) phase=\(.status.phase)"]),
    (select(.metadata.deletionTimestamp==null and .status.phase=="Running") |
      ([.status.conditions[]? | select(.type=="Ready")][0].status // "Missing") as $ready |
      select($ready!="True") | ["WARN", "pod \(.metadata.namespace)/\(.metadata.name) Ready=\($ready)"]),
    ((.status.containerStatuses[]?, .status.initContainerStatuses[]?) |
      select(.state.waiting.reason // "" | test("^(CrashLoopBackOff|ImagePullBackOff|ErrImagePull)$")) |
      ["WARN", "pod \($p.metadata.namespace)/\($p.metadata.name) container=\(.name) waiting=\(.state.waiting.reason)"])'
  rows "$WORK/pods" '[.items[] | . as $p | .status.containerStatuses[]? |
    (.state.running.startedAt // .state.terminated.startedAt // empty) as $start |
    select(($start | fromdateiso8601) >= ($now-$hours*3600)) |
    {minute:($start[0:16]), ns:$p.metadata.namespace, pod:$p.metadata.name, container:.name}] |
    group_by(.minute)[] | select(length >= $count and ([.[].ns]|unique|length) >= $namespaces) |
    ["WARN", "restart/start cluster-wide event (node/kubelet/storage), not app fault: \(.[0].minute)Z containers=\(length) namespaces=\([.[].ns]|unique|join(",")) pods=\([.[]|.ns+"/"+.pod]|unique|join(","))"]' \
    --argjson now "$NOW" --argjson hours "$STORM_HOURS" --argjson count "$STORM_CONTAINERS" --argjson namespaces "$STORM_NAMESPACES"
  record OK "Pod inventory checked: $(jq '.items|length' "$WORK/pods") pods; start-minute correlation is not restart history"
}
expiry() {
  local object=$1 seconds=$2 warn=$3 crit=$4 detail=${5:-} level=OK days
  if ! days=$(jq -en --arg s "$seconds" '$s|tonumber|select(isfinite and (isnan|not))|./86400'); then
    unavailable "$object validity"
    return
  fi
  if jq -en --argjson d "$days" --argjson c "$crit" '$d < $c' > /dev/null; then
    level=CRIT
  elif jq -en --argjson d "$days" --argjson w "$warn" '$d < $w' > /dev/null; then level=WARN; fi
  record "$level" "$object remaining_days=$days $detail"
}
k3s_certs() {
  local node subject usages seconds count line end epoch
  while IFS= read -r node; do
    if ! kube get --raw "/api/v1/nodes/$node/proxy/metrics" > "$WORK/cert-metrics"; then
      unavailable "node $node k3s certificates"
      continue
    fi
    if ! jq -Rn '[inputs | select(startswith("k3s_certificate_expiration_seconds{")) |
      capture("^k3s_certificate_expiration_seconds\\{(?<labels>.*)\\} (?<value>[^ ]+)") |
      .value as $v | [(.labels | capture("subject=\"(?<s>(?:[^\"\\\\]|\\\\.)*)\"").s),
      (.labels | capture("usages=\"(?<u>(?:[^\"\\\\]|\\\\.)*)\"").u)] + [$v]]' < "$WORK/cert-metrics" > "$WORK/certs"; then
      unavailable "node $node k3s certificate metric parse"
      continue
    fi
    count=$(jq length "$WORK/certs")
    if [[ "$count" == 0 ]]; then unavailable "node $node k3s certificates"; fi
    while IFS=$'\t' read -r subject usages seconds; do
      if [[ "$usages" == *CertSign* ]]; then
        expiry "node $node CA subject=$subject usages=$usages (manual CA renewal)" "$seconds" "$CA_WARN_DAYS" "$CA_CRIT_DAYS"
      else
        expiry "node $node leaf subject=$subject usages=$usages" "$seconds" "$CERT_WARN_DAYS" "$CERT_CRIT_DAYS"
      fi
    done < <(jq -r '.[] | @tsv' "$WORK/certs")
  done < <(jq -r '.items[].metadata.name' "$WORK/nodes")
  # Only the public certificate enters openssl; neither Secret JSON nor PEM is saved.
  if end=$(kube -n kube-system get secret k3s-serving -o 'jsonpath={.data.tls\.crt}' |
    base64 -d 2> /dev/null | openssl x509 -noout -enddate 2> /dev/null) && epoch=$(date -d "${end#notAfter=}" +%s 2> /dev/null); then
    expiry 'kube-system/k3s-serving leaf' "$((epoch - NOW))" "$CERT_WARN_DAYS" "$CERT_CRIT_DAYS" "$end"
  else unavailable 'kube-system/k3s-serving NotAfter'; fi
}
cert_manager() {
  get_json certificates certificates.cert-manager.io -A
  local obj ready notafter renewal failure attempts epoch level
  while IFS=$'\t' read -r obj ready notafter renewal failure attempts; do
    record OK "certificate $obj Ready=$ready renewalTime=$renewal notAfter=$notafter failedIssuanceAttempts=$attempts"
    level=WARN
    if [[ "$notafter" != '-' ]] && epoch=$(date -d "$notafter" +%s 2> /dev/null); then
      expiry "certificate $obj" "$((epoch - NOW))" "$CERT_WARN_DAYS" "$CERT_CRIT_DAYS" "renewalTime=$renewal notAfter=$notafter"
      if jq -en --argjson s "$((epoch - NOW))" --argjson c "$CERT_CRIT_DAYS" '$s < $c*86400' > /dev/null; then level=CRIT; fi
    else unavailable "certificate $obj notAfter"; fi
    if [[ "$ready" != True ]]; then record "$level" "certificate $obj Ready=$ready renewalTime=$renewal notAfter=$notafter"; fi
    if [[ "$renewal" != '-' ]] && epoch=$(date -d "$renewal" +%s 2> /dev/null); then
      if jq -en --argjson age "$((NOW - epoch))" --argjson grace "$RENEWAL_GRACE_HOURS" '$age > $grace*3600' > /dev/null; then
        record WARN "certificate $obj renewal overdue beyond grace (not proof of failure) renewalTime=$renewal notAfter=$notafter"
      fi
    else unavailable "certificate $obj renewalTime"; fi
    if [[ "$failure" != '-' ]] && epoch=$(date -d "$failure" +%s 2> /dev/null) &&
      jq -en --argjson age "$((NOW - epoch))" --argjson h "$FAILURE_HOURS" '$age >= 0 and $age <= $h*3600' > /dev/null; then
      record WARN "certificate $obj lastFailureTime=$failure failedIssuanceAttempts=$attempts renewalTime=$renewal notAfter=$notafter"
    fi
  done < <(jq -r '.items[] | [.metadata.namespace+"/"+.metadata.name,
    ([.status.conditions[]? | select(.type=="Ready")][0].status // "Missing"),
    (.status.notAfter // "-"),(.status.renewalTime // "-"),(.status.lastFailureTime // "-"),(.status.failedIssuanceAttempts // 0)] | @tsv' "$WORK/certificates")
}

prom_start() {
  kubectl --request-timeout="${TIMEOUT}s" -n "${K3S_HEALTH_PROM_NAMESPACE:-observability}" \
    port-forward --address 127.0.0.1 "svc/${K3S_HEALTH_PROM_SERVICE:-observability-kube-prometh-prometheus}" :9090 > "$WORK/forward" 2>&1 &
  PF_PID=$!
  local start=$SECONDS port
  while jq -en --argjson age "$((SECONDS - start))" --argjson max "$FORWARD_WAIT" '$age < $max' > /dev/null; do
    if ! kill -0 "$PF_PID" 2> /dev/null; then return 1; fi
    port=$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9]*\) -> .*/\1/p' "$WORK/forward")
    if [[ -n "$port" ]]; then
      PROM_URL="http://127.0.0.1:$port/api/v1/query"
      return 0
    fi
    sleep 0.2
  done
  return 1
}
query() {
  local name=$1 expression=$2
  if ! curl --fail --silent --max-time "$TIMEOUT" --get --data-urlencode "query=$expression" "$PROM_URL" > "$WORK/query" ||
    ! jq -e '.status=="success" and .data.resultType=="vector" and (.data.result|type=="array")' "$WORK/query" > /dev/null 2>&1; then
    unavailable "Prometheus $name query"
    return 1
  fi
  jq '.data.result' "$WORK/query" > "$WORK/$name"
  if [[ $(jq length "$WORK/$name") == 0 ]]; then unavailable "Prometheus $name"; fi
  rows "$WORK/$name" '.[] | select((try (.value[1]|tonumber|isfinite and (isnan|not)) catch false)|not) |
    ["INFO", "Prometheus \($name) nonfinite/invalid sample \(.metric|tojson) signal unavailable (N/A)"]' --arg name "$name"
}
capacity() {
  local name=$1 expression=$2 warn=$3 crit=$4
  query "$name" "$expression" || return 0
  if jq -e 'any(.[]; try (.value[1]|tonumber|isfinite and (isnan|not)) catch false)' "$WORK/$name" > /dev/null; then
    : > "$WORK/available-$name"
  fi
  rows "$WORK/$name" '.[] | (try (.value[1]|tonumber|select(isfinite and (isnan|not))) catch empty) as $v |
    [(if $v >= $crit then "CRIT" elif $v >= $warn then "WARN" else "OK" end),
    "\($name) \(.metric|tojson) used_percent=\($v)"]' --arg name "$name" --argjson warn "$warn" --argjson crit "$crit"
}
prometheus() {
  capacity memory '100 * (1 - node_memory_MemAvailable_bytes{job="node-exporter"} / node_memory_MemTotal_bytes{job="node-exporter"})' "$MEM_WARN_PERCENT" "$MEM_CRIT_PERCENT"
  local selector='job="node-exporter",fstype=~"ext[234]|xfs|btrfs|zfs|vfat|exfat|f2fs|bcachefs",mountpoint!~"/(dev|proc|sys)($|/.*)|/run/containerd/.*|/var/lib/(docker|kubelet)/.*"'
  capacity filesystem "100 * (1 - node_filesystem_avail_bytes{$selector} / node_filesystem_size_bytes{$selector}) and (node_filesystem_size_bytes{job=\"node-exporter\"} > 0) and (node_filesystem_readonly{job=\"node-exporter\"} == 0)" "$FS_WARN_PERCENT" "$FS_CRIT_PERCENT"
  if query filesystem_errors "max by(instance,device,mountpoint) ({__name__=~\"node_filesystem_readonly|node_filesystem_device_error\",$selector})"; then
    rows "$WORK/filesystem_errors" '.[] | (try (.value[1]|tonumber|select(isfinite and (isnan|not))) catch empty) as $v |
      [(if $v>0 then "WARN" else "OK" end), "filesystem readonly/device_error \(.metric|tojson) value=\($v)"]'
  fi
  capacity pvc 'max by(namespace,persistentvolumeclaim) ((100 * kubelet_volume_stats_used_bytes{job="kubelet",metrics_path="/metrics"} / kubelet_volume_stats_capacity_bytes{job="kubelet",metrics_path="/metrics"}) and (kubelet_volume_stats_capacity_bytes{job="kubelet",metrics_path="/metrics"} > 0))' "$PVC_WARN_PERCENT" "$PVC_CRIT_PERCENT"
  if [[ -f "$WORK/pvcs" && -f "$WORK/pvc" ]]; then
    rows "$WORK/pvcs" '.items[] | . as $p | select(any($samples[0][];
      .metric.namespace==$p.metadata.namespace and .metric.persistentvolumeclaim==$p.metadata.name and
      (try (.value[1]|tonumber|isfinite and (isnan|not)) catch false))|not) |
      ["INFO", "PVC \(.metadata.namespace)/\(.metadata.name) usage signal unavailable (N/A; unmounted/driver coverage possible)"]' --slurpfile samples "$WORK/pvc"
  fi
  if query restarts "sum by(namespace,pod,uid) (max by(namespace,pod,uid,container) (increase(kube_pod_container_status_restarts_total[${RESTART_HOURS}h])))"; then
    rows "$WORK/restarts" '.[] | (try (.value[1]|tonumber|select(isfinite and (isnan|not))) catch empty) as $v |
      [(if $v >= $warn then "WARN" else "OK" end), "restarts \(.metric.namespace)/\(.metric.pod) uid=\(.metric.uid) increase_\($hours)h=\($v)"]' --argjson warn "$RESTART_WARN" --arg hours "$RESTART_HOURS"
  fi
  if query availability 'apiserver_request:availability30d{verb="all"}'; then
    rows "$WORK/availability" '.[] | (try (.value[1]|tonumber|select(isfinite and (isnan|not))) catch empty) as $v |
      [(if $v*100 < $threshold then "WARN" else "OK" end), "API request-based availability30d \(.metric|tojson) percent=\($v*100)"]' --argjson threshold "$AVAILABILITY_PERCENT"
  fi
  if query targets 'up'; then
    rows "$WORK/targets" '.[] | (try (.value[1]|tonumber|select(isfinite and (isnan|not))) catch empty) as $v |
      [(if $v==0 then "WARN" else "OK" end), "Prometheus scrape \(.metric|tojson) up=\($v)"]'
    if ! jq -e 'any(.[]; .metric.job=="apiserver")' "$WORK/targets" > /dev/null; then unavailable 'Prometheus up{job="apiserver"}'; fi
  fi
}
top_usage() {
  local line
  if kube top pods -A --sort-by=memory > "$WORK/top-pods"; then
    record OK 'Top-5 pod memory consumers (current metrics-server usage):'
    while IFS= read -r line; do record OK "$line"; done < <(sed -n '1,6p' "$WORK/top-pods")
  else unavailable 'kubectl top pods -A'; fi
  if [[ ! -f "$WORK/available-memory" || ! -f "$WORK/available-filesystem" ]]; then
    unavailable 'Prometheus node memory/filesystem coverage; falling back to current kubectl top nodes/pods (no filesystem/history coverage)'
    if kube top nodes > "$WORK/top-nodes"; then
      while IFS= read -r line; do record OK "current node usage $line"; done < "$WORK/top-nodes"
    else unavailable 'kubectl top nodes'; fi
  fi
}
pvcs() {
  get_json pvcs pvc -A
  rows "$WORK/pvcs" '.items[] | [ (if .status.phase=="Lost" then "CRIT" elif .status.phase=="Bound" then "OK" else "WARN" end),
    "PVC \(.metadata.namespace)/\(.metadata.name) phase=\(.status.phase)"]'
}
longhorn() {
  get_json volumes volumes.longhorn.io -A
  get_json engines engines.longhorn.io -A
  rows "$WORK/volumes" '.items[] | . as $v |
    [(if .status.robustness=="faulted" then "CRIT" elif (.status.robustness // "unknown" | IN("healthy","unknown")) then "OK" else "WARN" end),
    "Longhorn volume \(.metadata.name) robustness=\(.status.robustness) state=\(.status.state) PVC=\(.status.kubernetesStatus.namespace)/\(.status.kubernetesStatus.pvcName)"],
    (select((.spec.nodeID // "")!="" and .status.state!="attached") |
      ["WARN", "Longhorn volume \(.metadata.name) requested attachment to \(.spec.nodeID) state=\(.status.state)"]),
    (.status.conditions[]? | select((.type=="Scheduled" and .status!="True") or
      (.type|IN("TooManySnapshots","Restore","FilesystemReadOnly")) and .status=="True") |
      ["WARN", "Longhorn volume \($v.metadata.name) condition=\(.type) status=\(.status)"]),
    (select(.status.state=="attached") |
      [$engines[0].items[] | select(.spec.volumeName==$v.metadata.name and .spec.active==true) |
        (.status.replicaModeMap // {} | to_entries[] | select(.value=="RW") | .key)] | unique | length as $ready |
      [(if $ready < $v.spec.numberOfReplicas then "WARN" else "OK" end),
      "Longhorn volume \($v.metadata.name) RW replicas=\($ready)/\($v.spec.numberOfReplicas)"])' --slurpfile engines "$WORK/engines"
}
longhorn_nodes() {
  get_json longhorn-nodes nodes.longhorn.io -A
  rows "$WORK/longhorn-nodes" '.items[] | . as $n |
    (.status.conditions[]? | select(.type|IN("Ready","Schedulable")) |
      [(if .status=="True" then "OK" else "WARN" end), "Longhorn node \($n.metadata.name) \(.type)=\(.status)"]),
    (select(.spec.allowScheduling==false) | ["INFO", "Longhorn node \(.metadata.name) scheduling disabled"])'
}
flux() {
  get_json flux kustomizations.kustomize.toolkit.fluxcd.io,helmreleases.helm.toolkit.fluxcd.io -A --show-managed-fields
  local object suspended ready stalled interval timestamp epoch seconds
  while IFS=$'\t' read -r object suspended ready stalled interval timestamp; do
    if [[ "$suspended" == true ]]; then
      record INFO "Flux $object suspended"
      continue
    fi
    if [[ "$stalled" == True ]]; then
      record CRIT "Flux $object Stalled=True"
    elif [[ "$ready" != True ]]; then
      record WARN "Flux $object Ready=$ready"
    else record OK "Flux $object Ready=True"; fi
    # Helm status writes track controller activity, not manual requests/releases.
    # managedFields time is a freshness proxy, not an exact reconcile timestamp.
    if [[ "$timestamp" == '-' ]]; then
      unavailable "Flux $object last-reconcile timestamp"
      continue
    fi
    if ! epoch=$(date -d "$timestamp" +%s 2> /dev/null) || ! seconds=$(jq -en --arg d "$interval" '
      [$d | scan("([0-9]+(?:\\.[0-9]+)?)(ms|h|m|s)") |
      (.[0]|tonumber) * (if .[1]=="h" then 3600 elif .[1]=="m" then 60 elif .[1]=="ms" then 0.001 else 1 end)] | add | select(.>0)'); then
      unavailable "Flux $object reconcile age/interval"
      continue
    fi
    if jq -en --argjson age "$((NOW - epoch))" --argjson interval "$seconds" --argjson factor "$FLUX_INTERVAL_MULTIPLIER" '$age > $interval*$factor' > /dev/null; then
      record WARN "Flux $object last-reconcile=$timestamp older than ${FLUX_INTERVAL_MULTIPLIER}x interval=$interval"
    else record OK "Flux $object last-reconcile=$timestamp interval=$interval"; fi
  done < <(jq -r '.items[] | [.kind+" "+.metadata.namespace+"/"+.metadata.name, (.spec.suspend // false),
    ([.status.conditions[]?|select(.type=="Ready")][0].status // "Missing"),
    ([.status.conditions[]?|select(.type=="Stalled")][0].status // "False"), .spec.interval,
    (if .kind=="HelmRelease" then
      [.metadata.managedFields[]? | select(.manager=="helm-controller" and .subresource=="status") | .time]
    else [.status.history[]?.lastReconciled] end | max // "-")] | @tsv' "$WORK/flux")
}
events() {
  get_json events events -A --field-selector=type=Warning
  rows "$WORK/events" '[.items[] |
    (.series.lastObservedTime // .lastTimestamp // .eventTime // .metadata.creationTimestamp) as $time |
    select((try ($time | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601) catch 0) >= $now-$hours*3600) |
    {reason,object:(.involvedObject|[.namespace,.kind,.name,(.uid // "")]|join("/")),count:(.series.count // .count // 1)}] |
    group_by([.reason,.object])[] | (map(.count)|add) as $count |
    [(if (.[0].reason|IN("FailedScheduling","FailedMount")) and $count >= $storm then "WARN" else "INFO" end),
    "Warning event \(.[0].reason) \(.[0].object) count=\($count) in last \($hours)h (event counts may span longer)"]' \
    --argjson now "$NOW" --argjson hours "$EVENT_HOURS" --argjson storm "$EVENT_STORM_COUNT"
}
edge() {
  if [[ ! -f "$WORK/pods" ]]; then
    unavailable 'Edge pod inventory'
    return
  fi
  rows "$WORK/pods" '.items[] | select(.metadata.namespace|IN("traefik","authentik","crowdsec")) |
    select(.metadata.deletionTimestamp==null and (.status.phase|IN("Succeeded","Failed")|not)) |
    [(if any(.status.conditions[]?; .type=="Ready" and .status=="True") then "OK" else "WARN" end),
    "edge pod \(.metadata.namespace)/\(.metadata.name) Ready=\([.status.conditions[]?|select(.type=="Ready")][0].status // "Missing")"]'
  rows "$WORK/pods" '[.items[] | select(.metadata.namespace=="traefik" and .metadata.labels["app.kubernetes.io/name"]=="traefik" and .metadata.deletionTimestamp==null) |
    select(any(.status.conditions[]?; .type=="Ready" and .status=="True"))] | length |
    [(if . < $replicas then "WARN" else "OK" end), "traefik ready replicas=\(.) expected=\($replicas)"]' --argjson replicas "$TRAEFIK_REPLICAS"
  local group ns expression count
  for group in server worker outpost lapi agent; do
    ns=authentik
    expression=$group
    if [[ "$group" == lapi || "$group" == agent ]]; then ns=crowdsec; fi
    count=$(jq --arg ns "$ns" --arg match "$expression" '[.items[] | select(.metadata.namespace==$ns and (.metadata.name|contains($match)) and .metadata.deletionTimestamp==null)]|length' "$WORK/pods")
    if [[ "$count" == 0 ]]; then record WARN "edge $ns/$group pods missing"; fi
  done
}
streaming() {
  local lapi pod ip line matches=0
  [[ -f "$WORK/pods" ]] || {
    unavailable 'crowdsec streaming pod inventory'
    return
  }
  lapi=$(jq -r '[.items[] | select(.metadata.namespace=="crowdsec" and .metadata.labels.type=="lapi")][0].metadata.name // empty' "$WORK/pods")
  if [[ -z "$lapi" ]] || ! kube -n crowdsec logs "$lapi" --since="${STREAM_SECONDS}s" --tail=5000 > "$WORK/lapi"; then
    unavailable 'crowdsec bouncer streaming logs'
    return
  fi
  # Match successful Traefik-plugin requests, not firewall bouncers using the same IP.
  grep -E 'GET /v1/decisions/stream.*HTTP/[0-9.]+ 200 .*Crowdsec-Bouncer-Traefik-Plugin/' "$WORK/lapi" > "$WORK/streams" || true
  while IFS=$'\t' read -r pod ip; do
    if [[ -z "$ip" || "$ip" == '-' ]]; then
      unavailable "traefik/$pod streaming IP"
      continue
    fi
    if grep -F "msg=\"$ip - " "$WORK/streams" > /dev/null; then
      record OK "traefik/$pod IP=$ip bouncer streaming decisions"
      matches=$((matches + 1))
    else record INFO "traefik/$pod IP=$ip bouncer streaming signal unavailable in last ${STREAM_SECONDS}s; possible wedged plugin (best-effort)"; fi
  done < <(jq -r '.items[] | select(.metadata.namespace=="traefik" and .metadata.labels["app.kubernetes.io/name"]=="traefik" and .metadata.deletionTimestamp==null) | [.metadata.name,(.status.podIP // "-")]|@tsv' "$WORK/pods")
  record OK "Bouncer streaming matched $matches traefik pod IPs"
}
jobs() {
  get_json jobs jobs -A
  rows "$WORK/jobs" '.items[] |
    [(if any(.status.conditions[]?; .type=="Failed" and .status=="True") or
      ((.status.failed // 0)>0 and (.status.succeeded // 0)==0) then "WARN" else "OK" end),
    "Job \(.metadata.namespace)/\(.metadata.name) failed=\(.status.failed // 0) succeeded=\(.status.succeeded // 0) active=\(.status.active // 0)"]'
}

for collector in nodes readyz pods k3s_certs cert_manager pvcs longhorn longhorn_nodes flux events edge streaming jobs; do run "$collector"; done
if prom_start; then
  run prometheus
else unavailable 'Prometheus loopback port-forward'; fi
run top_usage
record OK 'Health check complete'
finish
exit $?
