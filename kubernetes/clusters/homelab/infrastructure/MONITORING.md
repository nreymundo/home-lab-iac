# Monitoring Setup Guide

## Architecture

The homelab cluster uses Prometheus Operator for monitoring with cluster-wide discovery.

### Prometheus Configuration

Prometheus is configured to discover all ServiceMonitors and PodMonitors across all namespaces:
- `podMonitorSelectorNilUsesHelmValues: false`
- `serviceMonitorSelectorNilUsesHelmValues: false`

This means ANY ServiceMonitor or PodMonitor created in any namespace will be automatically discovered.

## Application Monitoring Status

| Application | Namespace | Type | Metrics Port | Status |
|------------|-----------|-------|--------------|--------|
| Kubernetes Components | various | Various | Varies | ✅ Monitored |
| Grafana | observability | ServiceMonitor | 3000 | ✅ Monitored |
| Kube State Metrics | observability | ServiceMonitor | 8080 | ✅ Monitored |
| Node Exporter | observability | ServiceMonitor | 9100 | ✅ Monitored |
| CloudNative-PG Databases | authentik | PodMonitor | 9187 | ✅ Monitored |
| Traefik | traefik | PodMonitor | 9100 | ✅ Monitored |
| Cert Manager | cert-manager | PodMonitor (Helm) | 9402 | ✅ Monitored |
| MetalLB Controller | metallb-system | PodMonitor | 7472 | ✅ Monitored |
| MetalLB Speaker | metallb-system | PodMonitor | 7472 | ✅ Monitored |
| Longhorn | longhorn-system | ServiceMonitor | 9500 | ✅ Monitored |
| Authentik Server | authentik | ServiceMonitor | 9300 | ✅ Monitored |
| Authentik Worker | authentik | ServiceMonitor | 9300 | ✅ Monitored |
| Loki | observability | ServiceMonitor (Helm) | 3100 | ✅ Monitored |
| Alloy | observability | ServiceMonitor | 12345 | ✅ Monitored |
| CloudNative-PG Operator | cnpg-system | PodMonitor | 8080 | ✅ Monitored |

## ServiceMonitor vs PodMonitor

### ServiceMonitor
Use when:
- Application exposes metrics via a Kubernetes Service
- Service has proper port definitions
- Multiple pods share the same service
- You want service-level metrics aggregation

Example:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: application
  namespace: app-namespace
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: application
  namespaceSelector:
    matchNames:
    - app-namespace
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

### PodMonitor
Use when:
- Application exposes metrics directly on pods
- Service doesn't expose metrics port
- You need pod-level metrics
- Application uses sidecar pattern

Example:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: application
  namespace: app-namespace
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: application
  podMetricsEndpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

## Common Metrics Ports

| Application | Port | Path | Type |
|------------|-------|------|------|
| Traefik | 9100 | /metrics | HTTP |
| Cert Manager | 9402 | /metrics | HTTP |
| MetalLB | 7472 | /metrics | HTTP |
| Longhorn | 9500 | /metrics | HTTP |
| Authentik | 9300 | /metrics | HTTP |
| Loki | 3100 | /metrics | HTTP |
| Alloy | 12345 | /metrics | HTTP |
| CloudNative-PG | 9187 | /metrics | HTTP |

## Adding Monitoring to New Applications

### Checklist

1. [ ] Check if application exposes metrics endpoints
2. [ ] Check if Helm chart supports ServiceMonitor
3. [ ] If Helm supports it, enable in Helm values
4. [ ] If Helm doesn't support it, create ServiceMonitor or PodMonitor
5. [ ] Add monitoring resource to `config/kustomization.yaml`
6. [ ] Update this MONITORING.md file
7. [ ] Test in Prometheus UI: http://grafana.lan.<DOMAIN>/d/kubernetes-prometheus

### Decision Tree

```
Application exposes metrics?
├─ No → Check Helm chart values for metrics enable flag
├─ Yes
   └─ Service exposes metrics port?
      ├─ Yes → Create ServiceMonitor
      └─ No → Create PodMonitor
```

## Verification

### Check Prometheus Targets
```bash
kubectl port-forward -n observability prometheus-observability-kube-prometh-prometheus-0 9090:9090
# Open http://localhost:9090/targets
```

All targets should show "UP" state.

### List ServiceMonitors and PodMonitors
```bash
kubectl get servicemonitors,podmonitors --all-namespaces
```

### Check Specific Application Monitoring
```bash
# Traefik
kubectl get podmonitor -n traefik traefik -o yaml

# Cert Manager
kubectl get podmonitor -n cert-manager -l app.kubernetes.io/name=cert-manager

# MetalLB
kubectl get podmonitor -n metallb-system

# Longhorn
kubectl get servicemonitor -n longhorn-system longhorn-manager

# Authentik
kubectl get servicemonitor -n authentik

# Loki
kubectl get servicemonitor -n observability -l app.kubernetes.io/name=loki

# Alloy
kubectl get servicemonitor -n observability -l app.kubernetes.io/name=alloy

# CloudNative-PG
kubectl get podmonitor -n cnpg-system
```

## Troubleshooting

### Target Not Appearing in Prometheus

1. Check if ServiceMonitor/PodMonitor exists:
   ```bash
   kubectl get servicemonitor -n <namespace> <name>
   kubectl get podmonitor -n <namespace> <name>
   ```

2. Check labels match:
   ```bash
   kubectl get pods -n <namespace> --show-labels
   kubectl get svc -n <namespace> --show-labels
   ```

3. Check Prometheus logs:
   ```bash
   kubectl logs -n observability prometheus-observability-kube-prometh-prometheus-0
   ```

4. Verify Prometheus discovery configuration:
   ```bash
   kubectl get prometheus -n observability -o yaml | grep -A 5 selector
   ```

### Metrics Not Being Collected

1. Check if metrics endpoint is accessible:
   ```bash
   kubectl port-forward -n <namespace> <pod-name> 8080:8080
   curl http://localhost:8080/metrics
   ```

2. Check ServiceMonitor/PodMonitor configuration:
   ```bash
   kubectl get servicemonitor <name> -n <namespace> -o yaml
   ```

3. Check Prometheus target status in UI for specific error message

### ServiceMonitor/PodMonitor Not Discovering Pods

1. Verify selector labels:
   ```bash
   kubectl get pods -n <namespace> --show-labels
   ```

2. Check ServiceMonitor/PodMonitor selectors:
   ```bash
   kubectl describe servicemonitor <name> -n <namespace>
   ```

3. Ensure pods are running:
   ```bash
   kubectl get pods -n <namespace>
   ```

## Reference

- Prometheus Operator: https://prometheus-operator.dev/
- Flux Documentation: https://fluxcd.io/flux/
- Monitoring Best Practices: https://prometheus.io/docs/practices/naming/
