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

  ## Authentik Secrets

Two separate BitwardenSecrets manage Authentik credentials:

1. **PostgreSQL credentials** (`postgres-creds`):
   - Used by CNPG to create the `authentik` database user
   - Used by Authentik to connect to the database
   - Contains: `username` (static value: "authentik"), `password` (generated secure password)

2. **Authentik application secret** (`authentik-secret`):
   - Used by Authentik for cookie signing, JWT token generation, and cryptographic operations
   - Contains: `secret_key` (generate with: `openssl rand -base64 48`)

### Steps:

1. Generate Authentik secret key:
   ```sh
   openssl rand -base64 48
   ```

2. Create secrets in Bitwarden:
   - PostgreSQL username secret with ID (value: "authentik")
   - PostgreSQL password secret with ID (generate secure password)
   - Authentik secret key secret with ID (use generated value from step 1)

3. Update the sample file:
   ```sh
   vim kubernetes/clusters/homelab/secrets/bitwarden-authentik-secret.sample.yaml
   ```
   Replace placeholder IDs:
   - `REPLACE_ME_BITWARDEN_ORG_ID`
   - `REPLACE_ME_POSTGRES_USERNAME_SECRET_ID`
   - `REPLACE_ME_POSTGRES_PASSWORD_SECRET_ID`
   - `REPLACE_ME_AUTHENTIK_SECRET_KEY_ID`

4. Apply the secrets:
   ```sh
   kubectl apply -f kubernetes/clusters/homelab/secrets/bitwarden-authentik-secret.yaml
   ```

5. Verify:
   ```sh
   kubectl -n authentik get secret postgres-creds
   kubectl -n authentik get secret authentik-secret
   ```

Flux will automatically reconcile the HelmRelease changes, and Authentik pods should restart and come up successfully.
