# OpenTelemetry Gateway

The collector accepts authenticated OTLP telemetry from cluster workloads, LAN
clients, and NetBird peers. It routes metrics to Prometheus, logs to Loki, and
traces to Tempo.

## Endpoints

| Scope | Protocol | Endpoint |
| --- | --- | --- |
| Cluster | OTLP/gRPC | `opentelemetry-collector.observability.svc.cluster.local:4317` |
| Cluster | OTLP/HTTP | `http://opentelemetry-collector.observability.svc.cluster.local:4318` |
| LAN/NetBird | OTLP/gRPC | `https://otel-grpc.lan.${CLUSTER_DOMAIN}` |
| LAN/NetBird | OTLP/HTTP | `https://otel.lan.${CLUSTER_DOMAIN}` |

Both receivers require HTTP Basic authentication. The encrypted Secret contains
an `opencode` credential for OpenCode clients and a `systems` credential for
other producers. Add separate users when independent revocation is required.

## Read Client Credentials

Run these commands locally from the repository. Do not paste the output into
Git, logs, or chat transcripts.

```bash
secret_file=kubernetes/infrastructure/observability/opentelemetry-collector/install/auth.sops.yaml
username=$(sops --decrypt "$secret_file" | yq -r '.data.OPENCODE_USERNAME' | base64 -d)
password=$(sops --decrypt "$secret_file" | yq -r '.data.OPENCODE_PASSWORD' | base64 -d)
auth=$(printf '%s:%s' "$username" "$password" | base64 -w0)
```

## OpenCode Client

Install `@devtheops/opencode-plugin-otel` in each OpenCode configuration and set
the options below. Keep the authorization value in an environment variable or
secret manager rather than committing it.

```jsonc
{
  "plugin": [
    ["@devtheops/opencode-plugin-otel", {
      "enabled": true,
      "endpoint": "https://otel.lan.example.com",
      "protocol": "http/protobuf",
      "otlpHeaders": "{env:OPENCODE_OTLP_HEADERS}",
      "resourceAttributes": "service.name=opencode,service.instance.id=desktop,deployment.environment=home"
    }]
  ]
}
```

```bash
export OPENCODE_OTLP_HEADERS="Authorization=Basic $auth"
```

Use a stable and unique `service.instance.id` for each OpenCode installation.
The collector removes session, message, request, trace, and span identifiers
from metric labels to limit Prometheus cardinality. Logs and traces retain their
correlation identifiers.

## Prometheus Storage Expansion

The desired Prometheus volume is 100 GiB with a 30-day time limit and an 85 GiB
size limit. Kubernetes cannot propagate a larger claim template to an existing
StatefulSet automatically. After Flux applies the desired Prometheus resource,
perform this one-time controlled resize:

```bash
flux suspend kustomization observability-kube-prometheus-stack-install

kubectl -n observability patch prometheus observability-kube-prometh-prometheus \
  --type merge -p '{"spec":{"paused":true}}'

kubectl -n observability patch pvc \
  prometheus-observability-kube-prometh-prometheus-db-prometheus-observability-kube-prometh-prometheus-0 \
  --type merge -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

kubectl -n observability delete statefulset \
  prometheus-observability-kube-prometh-prometheus --cascade=orphan

kubectl -n observability patch prometheus observability-kube-prometh-prometheus \
  --type merge -p '{"spec":{"paused":false}}'

flux resume kustomization observability-kube-prometheus-stack-install
```

Confirm the PVC reports 100 GiB and Prometheus returns to ready before enabling
additional producers.

## Verification

After Flux reconciliation:

```bash
flux get kustomizations
flux get helmreleases -A
kubectl -n observability get pods,svc,pvc
```

Collector health is monitored through its ServiceMonitor and default
PrometheusRule alerts. Use Grafana Explore to verify metrics in Prometheus, logs
in Loki, and traces in Tempo before expanding ingestion.
