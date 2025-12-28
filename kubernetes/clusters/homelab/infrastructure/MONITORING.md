# Monitoring Setup Guide

> **Note:** For a full overview of the Observability stack (Loki, Grafana, etc.), please see [**observability/README.md**](observability/README.md).

## Architecture

The homelab cluster uses **kube-prometheus-stack** (Prometheus Operator) for monitoring with cluster-wide discovery.

### Prometheus Configuration

Prometheus is configured to discover all ServiceMonitors and PodMonitors across all namespaces:
- `podMonitorSelectorNilUsesHelmValues: false`
- `serviceMonitorSelectorNilUsesHelmValues: false`

This means ANY ServiceMonitor or PodMonitor created in any namespace will be automatically discovered.

## Application Monitoring Status

| Application | Namespace | Type | Port | Status |
|------------|-----------|-------|------|--------|
| Kubernetes Components | various | Various | Varies | ✅ Monitored |
| Grafana | observability | ServiceMonitor | 3000 | ✅ Monitored |
| Node Exporter | observability | ServiceMonitor | 9100 | ✅ Monitored |
| CloudNative-PG | authentik | PodMonitor | 9187 | ✅ Monitored |
| Traefik | traefik | PodMonitor | 9100 | ✅ Monitored |
| Cert Manager | cert-manager | PodMonitor | 9402 | ✅ Monitored |
| MetalLB | metallb-system | PodMonitor | 7472 | ✅ Monitored |
| Longhorn | longhorn-system | ServiceMonitor | 9500 | ✅ Monitored |
| Authentik | authentik | ServiceMonitor | 9300 | ✅ Monitored |
| Loki | observability | ServiceMonitor | 3100 | ✅ Monitored |
| Alloy | observability | ServiceMonitor | 12345 | ✅ Monitored |

## ServiceMonitor vs PodMonitor

### ServiceMonitor
Use when the application exposes metrics via a Kubernetes **Service**.
Preferred method if a service exists.

### PodMonitor
Use when you need to scrape pods directly (e.g., sidecars, headless services, or if no service exposes the metrics port).

## Adding Monitoring to New Applications

### Checklist

1. [ ] Check if application exposes metrics endpoints (usually `/metrics`).
2. [ ] Check if Helm chart supports `serviceMonitor.enabled: true`.
3. [ ] If yes, enable it in `values.yaml`.
4. [ ] If no, create a `ServiceMonitor` manifest manually.
5. [ ] Verify target appears in Prometheus: `http://prometheus.lan.<DOMAIN>/targets`.

## Troubleshooting

### Target Not Appearing
1.  Check labels! The ServiceMonitor `selector` must match the Service's `labels`.
    ```bash
    kubectl get svc my-app --show-labels
    kubectl get servicemonitor my-app -o yaml
    ```
2.  Check Prometheus logs.
    ```bash
    kubectl logs -n observability -l app.kubernetes.io/name=prometheus
    ```

### "Connection Refused"
1.  Is the pod listening on that port?
2.  Is the named port correct?

## References
- [Prometheus Operator Docs](https://prometheus-operator.dev/)
- [Observability README](observability/README.md)
