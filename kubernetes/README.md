# Kubernetes GitOps

This folder is managed with Flux. Charts, configs, and other installs are defined in Git
and continuously reconciled to the cluster in a GitOps workflow.

If the cluster needs to be recreated from scratch, bootstrap Flux manually using the Flux CLI to re-establish the GitOps sync. For example:

    flux bootstrap github \
      --owner=nreymundo \
      --repository=home-lab-iac \
      --branch=master \
      --path=./kubernetes/clusters/homelab \
      --private-key-file=<path-to-your-ssh-key>

For more information, see the [Flux bootstrap documentation](https://fluxcd.io/flux/cmd/flux_bootstrap_github/).

## Naming Conventions

When adding new Helm releases, always include `fullnameOverride` in the `values` section to prevent redundant resource names (e.g., to avoid `traefik-traefik`).

```yaml
values:
  fullnameOverride: <APP_NAME>
```

See `kubernetes/samples/helm_release_template.yaml` for a complete example.

## Samples

Check the `kubernetes/samples/` directory for templates:
- `helm_release_template.yaml`: Standard Flux HelmRelease.
- `stateless_web_app.yaml`: Deployment + Service + Ingress (SSL/LAN-only).
- `stateless_web_app_with_authentik.yaml`: Deployment + Service + Ingress (SSL/LAN-only/Authentik).
- `proxy_external_service*.yaml`: Expose external IPs via Traefik Ingress.
- `proxy_external_service_with_ssl_and_authentik.yaml`: Expose external HTTPS IPs with Authentik authentication.
- `db_with_cloudnativepg.yaml`: Postgres cluster with labels.
