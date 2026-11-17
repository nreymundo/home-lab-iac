# OpenTelemetry Gateway

The collector accepts authenticated OTLP from cluster and allowed LAN clients.
`observability-opentelemetry-collector-install` reconciles [install/](install/kustomization.yaml)
after Traefik config and the Prometheus, Loki, and Tempo installs. It sends
metrics to Prometheus's OTLP HTTP receiver, logs to the Loki gateway's OTLP
endpoint, and traces to Tempo over OTLP/gRPC.

## Endpoints

| Scope | Protocol | Endpoint |
| --- | --- | --- |
| Cluster | OTLP/gRPC | `opentelemetry-collector.observability.svc.cluster.local:4317` |
| Cluster | OTLP/HTTP | `http://opentelemetry-collector.observability.svc.cluster.local:4318` |
| LAN ingress | OTLP/gRPC | `https://otel-grpc.lan.${CLUSTER_DOMAIN}` |
| LAN ingress | OTLP/HTTP | `https://otel.lan.${CLUSTER_DOMAIN}` |

Both receivers require HTTP Basic authentication. The encrypted Secret contains
an `opencode` credential for OpenCode clients and a `systems` credential for
other producers. Add separate users when independent revocation is required.

Traefik applies `opentelemetry-allowlist` to both ingress routes and uses h2c
between Traefik and the gRPC Service. The allowlist retains the pod CIDR for
the historical NetBird design, but NetBird ingress is disabled in production.
Executor uses its own `executor-otel-secret`, sourced in this install inventory
and replicated into `ai` for its HelmRelease.

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

## Prometheus capacity

The [Prometheus HelmRelease](../kube-prometheus-stack/install/helmrelease.yaml)
requests `100Gi` of storage, with `30d` time retention and an `85GiB` size
limit. On an existing cluster, verify actual claim capacity separately from
the desired claim template before increasing ingestion.

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
