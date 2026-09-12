---
name: kubernetes-observability-debugging
description: >-
  Debug and configure this repo's centralized observability stack under
  `kubernetes/infrastructure/observability/` — kube-prometheus-stack
  (Prometheus + Grafana), Loki, Tempo, Alloy, Alloy-syslog,
  OpenTelemetry Collector, and metrics-server. Use when the user says
  "Grafana datasource is missing/broken", "Loki/Tempo logs/traces not flowing",
  "Prometheus target down", "ServiceMonitor not scraped", "Alloy/OTel pipeline
  failing", or "Grafana provisioning reset/lost". Especially relevant for
  Grafana datasource UID stability, provisioned-at-startup resources, and the
  OTel → Tempo → Loki → Grafana wiring. Do NOT use for app-level logging
  questions, Alertmanager rule authoring outside this stack, or general
  workload onboarding.
---

# Kubernetes Observability Debugging

This is a centralized pipeline: Alloy and OTel collect, Loki stores logs,
Tempo stores traces, Prometheus stores metrics, Grafana visualizes. Recent
history shows repeated breakage specifically around Grafana provisioning and
datasource UID stability — handle those areas carefully.

## When to use

- Grafana datasource missing, duplicated, or wrong UID.
- Logs/traces/metrics not flowing through the central pipeline.
- ServiceMonitor / PodMonitor not scraped by Prometheus.
- OTel Collector or Alloy pipeline errors.
- Grafana resources (dashboards, datasources) disappeared after a restart.
- Reset or re-shape Grafana provisioning.

Do not use for app-specific log volume questions, alert authoring outside this
stack, or workload onboarding.

## Stack layout

```
kubernetes/infrastructure/observability/
  kube-prometheus-stack/install/   # Prometheus, Alertmanager, Grafana, operator
  loki/install/                    # log storage + gateway
  tempo/install/                   # trace storage
  alloy/install/                   # log/metric collection
  alloy-syslog/install/            # syslog ingestion
  opentelemetry-collector/install/ # centralized OTel ingestion
  metrics-server/install/          # kube resource metrics
```

All `install/`-only — verify whether a `config/` overlay exists before assuming
runtime config lives elsewhere.

## High-signal debugging sequence

1. **Direction first**: identify which leg is broken — collection (Alloy/OTel),
   storage (Loki/Tempo/Prometheus), or visualization (Grafana).
2. **Collection**:
   - `kubectl -n observability get pods -l app.kubernetes.io/name=alloy`
   - `kubectl -n observability logs <alloy-pod>`
   - OTel: `kubectl -n observability get pods -l app.kubernetes.io/name=opentelemetry-collector`
     and check the collector's telemetry/exporter logs.
3. **Storage**:
   - Loki: `kubectl -n observability get pods -l app.kubernetes.io/name=loki`;
     verify the gateway and backend pods are ready.
   - Tempo: same pattern; trace ingestion depends on OTel exporter config.
   - Prometheus: `kubectl get prometheus,podmonitor,servicemonitor -A`
     (cluster-wide; these CRs may live in any namespace).
4. **Visualization (Grafana)**: see section below — this is the most fragile
   area in recent history.
5. **End-to-end**: confirm a known-good log/traces/metric query returns data in
   Grafana before declaring the pipeline healthy.

## Grafana provisioning (fragile — read before editing)

Recent commits show repeated trouble with: provisioned datasource UID
stability, startup-time resource provisioning, decoupled Tempo datasource
provisioning, and OTel integration. When changing Grafana provisioning:

- Preserve existing datasource **UIDs** — dashboards reference them by UID, not
  by name. Renaming without keeping the UID silently breaks every dashboard
  that uses that datasource.
- Prefer **provision at startup** over imperative creation so a Grafana restart
  returns to a known state. If a datasource keeps "disappearing", it is usually
  a provisioning-vs-runtime conflict.
- Keep Tempo and Loki provisioning **decoupled** so a failure in one does not
  block the other.
- When integrating OTel, verify the collector's exporter endpoint and the
  Grafana datasource point at the same in-cluster service.

## Validation

```bash
# Render. There is NO root kubernetes/infrastructure/observability/kustomization.yaml —
# Flux reconciles each component's install dir individually, so render the
# changed component(s) explicitly:
kubectl kustomize kubernetes/infrastructure/observability/<component>/install >/dev/null
# (e.g. .../loki/install, .../tempo/install, .../kube-prometheus-stack/install)
kubectl kustomize kubernetes/infrastructure >/dev/null   # root infra kustomization exists
scripts/kubeconform.sh
# pre-commit needs explicit file paths — bash's `**` does not recurse without
# `shopt -s globstar`, so enumerate YAML files explicitly:
pre-commit run --files $(find kubernetes/infrastructure/observability -type f)

# Live (only if reachable + intended)
kubectl -n observability get pods
kubectl get prometheus,servicemonitor,podmonitor -A
flux get helmreleases -A | grep -E 'loki|tempo|alloy|kube-prometheus|opentelemetry'
```

## Anti-patterns

- Changing a datasource `uid` without auditing dashboard references.
- Imperatively creating datasources that the provisioning layer will then
  conflict with on next restart.
- Treating an OTel or Alloy config change as local — verify the downstream
  storage and Grafana datasource still match.
- Using `kubectl apply` against live objects to "test" when `kubectl
  kustomize` + `--dry-run=client` answers the question.

## References

- `kubernetes/infrastructure/AGENTS.md`, `kubernetes/AGENTS.md`
- `kubernetes/infrastructure/observability/*/install/`
- `kubernetes/clusters/production/ks/` (reconciliation order)
- Recent history (Grafana provisioning cluster): commits `ca1cdb2`, `be1e5d7`,
  `14ddafb`, `c2fcf9b`, `186ed05`, `cb2ca70`, `1af2cc6`, `45171e0`
