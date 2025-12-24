# Manual secrets

This folder stores sample manifests for secrets that must be created manually in the cluster.
Values in these files are placeholders.

I know the files take IDs and not the actual secrets or credentials and should therefore be safe to commit but I'm just being extra paranoid on this.

## Cert Manager Secrets

Creates `cert-manager-secrets` in both `cert-manager` and `flux-system` via the Bitwarden operator.
Flux substitutions for cert-manager config read from the `flux-system` Secret,
and cert-manager reads the Cloudflare API token from the `cert-manager` Secret at runtime.
The `flux-system` Secret uses `ACME_EMAIL` and `DOMAIN_NAME` keys because Flux envsubst
requires variable names without hyphens.

Steps:

- Copy `bitwarden-cert-manager-secrets.sample.yaml` to `bitwarden-cert-manager-secrets.yaml`.
- Edit `bitwarden-cert-manager-secrets.yaml` and replace the placeholder IDs.
- Ensure the Bitwarden auth token Secret exists in both `cert-manager` and `flux-system`.
- We're using Kubernetes Replicator to share the machine user for Bitwarden accross namespaces, annotate the source Secret to include `cert-manager` as a target, for example: `replicator.v1.mittwald.de/replicate-to: flux-system,cert-manager`.
- `kubectl apply -f bitwarden-cert-manager-secrets.yaml`

Example:
```sh
cp bitwarden-cert-manager-secrets.sample.yaml bitwarden-cert-manager-secrets.yaml
vim bitwarden-cert-manager-secrets.yaml
kubectl apply -f bitwarden-cert-manager-secrets.yaml
kubectl -n cert-manager get secret cert-manager-secrets
```
