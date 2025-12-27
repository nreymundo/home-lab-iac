# CloudNative-PG Monitoring Configuration

This document explains how to enable Prometheus metrics collection for CloudNative-PG database clusters.

## Overview

CloudNative-PG provides built-in Prometheus metrics for PostgreSQL clusters. To enable metrics collection:

1. Enable PodMonitor creation for each cluster
2. Prometheus automatically discovers and scrapes metrics via PodMonitor
3. Metrics are available on port 9187 with `cnpg_` prefix

## Enabling Metrics for a Cluster

When creating or modifying a `Cluster` resource, add a `monitoring` section:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <cluster-name>
  namespace: <namespace>
spec:
  instances: 1
  storage:
    size: 5Gi
    storageClass: longhorn
  enableSuperuserAccess: false

  # Enable Prometheus monitoring
  monitoring:
    enablePodMonitor: true
    disableDefaultQueries: false
    customQueriesConfigMap:
      - name: cnpg-default-monitoring
        key: queries
```

### Configuration Options

- `enablePodMonitor: true` - Automatically creates a PodMonitor resource for this cluster
- `disableDefaultQueries: false` - Include built-in metrics queries (recommended)
- `customQueriesConfigMap` - Reference to custom metric queries ConfigMap

## Default Queries ConfigMap

The CloudNative-PG operator installs a default ConfigMap named `cnpg-default-monitoring` in the operator's namespace containing a comprehensive set of metrics queries for:

- Connection statistics
- Replication lag
- WAL usage
- Transaction rates
- Table sizes
- Index usage

Reference this ConfigMap in your cluster definition to include these metrics.

## Verification

After enabling monitoring, verify:

1. **PodMonitor created:**
   ```bash
   kubectl get podmonitor -n <namespace>
   ```

2. **Metrics accessible:**
   ```bash
   kubectl exec -n <namespace> pod/<cluster-name>-1 -- \
     wget -qO- http://localhost:9187/metrics | head -30
   ```

3. **Prometheus target:**
   - Port-forward to Prometheus UI
   - Navigate to `/targets`
   - Look for `<cluster-name>` target with "UP" state

## Best Practices

- **Enable monitoring for all production clusters:** Don't leave production databases unmonitored
- **Use separate namespace per application:** Helps organize resources and access control
- **Review metrics in Grafana dashboards:** Use CloudNative-PG dashboard (gnetId: 20417)
- **Monitor replication:** For high-availability clusters with multiple instances, monitor replication lag and failover events

## Troubleshooting

### PodMonitor not created
- Check CloudNative-PG operator logs: `kubectl logs -n cnpg-system deployment/cnpg-controller-manager`
- Verify Prometheus has RBAC access to discover PodMonitors
- Check Cluster resource YAML for correct monitoring section

### Metrics not appearing in Prometheus
- Verify PodMonitor labels match Prometheus ServiceMonitor/PodMonitor label selectors
- Check Prometheus logs for scrape errors
- Ensure metrics endpoint is accessible from Prometheus pod

## References

- [CloudNative-PG Monitoring Documentation](https://cloudnative-pg.io/documentation/current/monitoring/)
- [CloudNative-PG Grafana Dashboard](https://grafana.com/grafana/dashboards/20417-cloudnativepg/)
- [Grafana Dashboard Source](https://github.com/cloudnative-pg/grafana-dashboards)
