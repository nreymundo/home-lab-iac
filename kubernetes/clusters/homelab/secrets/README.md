# Manual secrets

This folder stores sample manifests for secrets that must be created manually in cluster.
Values in these files are placeholders.

I know the files take IDs and not the actual secrets or credentials and should therefore be safe to commit but I'm just being extra paranoid on this.

## Bitwarden Auth Token Replication

We use mittwald Kubernetes Replicator to copy the `bw-access-token` Secret into any namespace that needs Bitwarden secrets. Annotate the source Secret to include all required targets, for example:

```sh
kubectl -n <source-namespace> annotate secret bw-access-token \
  'replicator.v1.mittwald.de/replicate-to=flux-system,cert-manager,external-dns,authentik' --overwrite
```

Update the list as you add/remove namespaces that need Bitwarden-managed secrets.

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
- `kubectl apply -f bitwarden-cert-manager-secrets.yaml`

Example:
```sh
cp bitwarden-cert-manager-secrets.sample.yaml bitwarden-cert-manager-secrets.yaml
vim bitwarden-cert-manager-secrets.yaml
kubectl apply -f bitwarden-cert-manager-secrets.yaml
kubectl -n cert-manager get secret cert-manager-secrets
```

## ExternalDNS Pi-hole Secret

Creates `external-dns-pihole` in `external-dns` via the Bitwarden operator to supply the Pi-hole admin password for ExternalDNS.

Steps:

- Copy `bitwarden-external-dns-pihole.sample.yaml` to `bitwarden-external-dns-pihole.yaml`.
- Edit `bitwarden-external-dns-pihole.yaml` and replace the placeholder Bitwarden organization/secret IDs.
- Ensure the Bitwarden auth token Secret exists in the `external-dns` namespace.
- `kubectl apply -f bitwarden-external-dns-pihole.yaml`

Example:
```sh
cp bitwarden-external-dns-pihole.sample.yaml bitwarden-external-dns-pihole.yaml
vim bitwarden-external-dns-pihole.yaml
kubectl apply -f bitwarden-external-dns-pihole.yaml
kubectl -n external-dns get secret external-dns-pihole
```

## Authentik Database Secrets

Creates PostgreSQL credentials for Authentik, reused by both CNPG (database) and Authentik application.

Two Bitwarden secrets are needed:
- PostgreSQL username (stored as static value: "authentik")
- PostgreSQL password (generated secure password)

Single Kubernetes secret `postgres-creds` is created with both username and password:
- CNPG uses it to create the `authentik` database user
- Authentik uses it to connect to the database

Steps:

- Copy `bitwarden-authentik-db-secret.sample.yaml` to `bitwarden-authentik-db-secret.yaml`.
- Edit and replace placeholder Bitwarden organization/secret IDs:
  - `REPLACE_ME_BITWARDEN_ORG_ID`
  - `REPLACE_ME_POSTGRES_USERNAME_SECRET_ID`
  - `REPLACE_ME_POSTGRES_PASSWORD_SECRET_ID`
- Ensure the Bitwarden auth token Secret exists in the `authentik` namespace.
- `kubectl apply -f bitwarden-authentik-db-secret.yaml`

Example:
```sh
cp bitwarden-authentik-db-secret.sample.yaml bitwarden-authentik-db-secret.yaml
vim bitwarden-authentik-db-secret.yaml
kubectl apply -f bitwarden-authentik-db-secret.yaml
kubectl -n authentik get secret postgres-creds
```
