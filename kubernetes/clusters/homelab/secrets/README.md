# Manual secrets

This folder stores sample manifests for secrets that must be created manually in the cluster.
Values in these files are placeholders.

I know the files take IDs and not the actual secrets or credentials and should therefore be safe to commit but I'm just being extra paranoid on this.

## Cert Manager Secrets

Creates `cert-manager-secrets` in the `cert-manager` namespace via the Bitwarden operator.
Flux substitutions for cert-manager config read from this Secret via `substituteFrom.namespace`,
and cert-manager reads the Cloudflare API token from the same Secret at runtime.

Steps:

- Copy `bitwarden-cert-manager-secrets.sample.yaml` to `bitwarden-cert-manager-secrets.yaml`.
- Edit `bitwarden-cert-manager-secrets.yaml` and replace the placeholder IDs.
- Ensure the Bitwarden auth token Secret exists in `cert-manager`.
- We're using Kubernetes Replicator to share the machine user for Bitwarden accross namespaces, annotate the source Secret to include `cert-manager` as a target, for example: `replicator.v1.mittwald.de/replicate-to: flux-system,cert-manager`.
- `kubectl apply -f bitwarden-cert-manager-secrets.yaml`

Example:
```sh
cp bitwarden-cert-manager-secrets.sample.yaml bitwarden-cert-manager-secrets.yaml
vim bitwarden-cert-manager-secrets.yaml
kubectl apply -f bitwarden-cert-manager-secrets.yaml
kubectl -n cert-manager get secret cert-manager-secrets
```
