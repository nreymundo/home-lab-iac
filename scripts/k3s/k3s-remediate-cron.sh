#!/usr/bin/env bash
# Cron wrapper for the Hermes host: refresh a dedicated ops clone from
# origin/master, then run the health check and tier 0/1 remediation.
# Prints nothing on success; prints one line per infrastructure error
# (fetch/reset/syntax). Remediation failures log to the audit log.
# The dedicated clone (K3S_OPS_CLONE, default ~/ops/home-lab-iac) exists
# so worker worktrees and feature checkouts never fight over it. Repo
# updates take effect on the next run after merging to master; if a
# script fails the syntax check on origin/master the run is skipped
# rather than executing a broken version. Sibling scripts are resolved
# relative to this file's own directory.
# Intended crontab entry (hourly):
#   0 * * * * /bin/bash ~/ops/home-lab-iac/scripts/k3s/k3s-remediate-cron.sh >> ~/.local/state/k3s-remediate/cron.log 2>&1
set -uo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
CLONE=${K3S_OPS_CLONE:-$HOME/ops/home-lab-iac}
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STAMP() { date -u +%FT%TZ; }

mkdir -p "${K3S_REM_STATE:-$HOME/.local/state/k3s-remediate}" || exit 1
cd "$CLONE" || {
  echo "$(STAMP) ops clone missing: $CLONE"
  exit 1
}
git fetch --quiet origin || {
  echo "$(STAMP) git fetch failed"
  exit 1
}
git reset --hard --quiet origin/master || {
  echo "$(STAMP) git reset failed"
  exit 1
}
bash -n "$DIR/k3s-health-check.sh" || {
  echo "$(STAMP) k3s-health-check.sh failed syntax check on origin/master"
  exit 1
}
bash -n "$DIR/k3s-remediate.sh" || {
  echo "$(STAMP) k3s-remediate.sh failed syntax check on origin/master"
  exit 1
}

# Non-zero health-check exits are normal findings, not wrapper errors.
bash "$DIR/k3s-health-check.sh" > /dev/null 2>&1 || true
bash "$DIR/k3s-remediate.sh" --apply > /dev/null 2>&1
rc=$?
# 0 = ran clean, 2 = circuit breaker (expected protection, logged); only
# real errors surface here.
if ((rc == 1)); then
  echo "$(STAMP) k3s-remediate.sh error exit (see ${K3S_REM_STATE:-$HOME/.local/state/k3s-remediate}/actions.log)"
  exit 1
fi
exit 0
