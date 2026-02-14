# Authentik Configuration

## Directory Structure

```
authentik/
├── install/                         # HelmRelease and bootstrap resources
│   ├── helmrelease.yaml             # Authentik server deployment
│   ├── blueprint-bootstrap-cm.yaml  # SSO blueprints (ConfigMap)
│   ├── authentik-env.sops.yaml      # Environment secrets
│   └── *-sso-secret.sops.yaml       # Per-app OAuth2 client secrets
└── config/                          # Runtime configuration
    ├── middleware.yaml              # Traefik forwardAuth middleware (shared)
    ├── middleware-frigate.yaml      # Frigate-specific middleware
    └── ingress.yaml                 # Authentik ingress
```

## Blueprint Structure

The bootstrap ConfigMap contains multiple YAML blueprints loaded alphabetically by filename:

| File | Purpose | Models Created |
|------|---------|----------------|
| `10-bootstrap.yaml` | Admin user, Traefik-Gatekeeper provider | User, Group, ProxyProvider, Application |
| `20-grafana.yaml` | Grafana OAuth2 SSO | Group, OAuth2Provider, Application |
| `30-vaultwarden.yaml` | Vaultwarden OAuth2 SSO | Group, ScopeMapping, OAuth2Provider, Application |
| `40-audiobookshelf.yaml` | Audiobookshelf OAuth2 SSO | Group, OAuth2Provider, Application |
| `50-komga.yaml` | Komga OAuth2 SSO | OAuth2Provider, Application |
| `60-gitea.yaml` | Gitea OAuth2 SSO | Group, ScopeMapping, OAuth2Provider, Application |
| `70-frigate.yaml` | Frigate proxy auth | Group, ScopeMapping, ProxyProvider, Application |
| `99-outpost.yaml` | Shared outpost (MUST BE LAST) | Outpost |

### Critical: Outpost Ordering

**The outpost MUST be defined in `99-outpost.yaml` (last).**

Blueprint `attrs` **replaces** entire objects, it does not merge. If an outpost is defined in multiple files:
- Later blueprints **overwrite** earlier outpost configs
- Partial updates will **wipe** missing fields (`type`, `service_connection`, `config`)

**Rule:** ALL proxy providers must be registered BEFORE the outpost blueprint runs.

## Adding a New SSO Application

### For OAuth2 Applications (most apps)

1. **Create client secret** (if confidential client):
   ```bash
   cd kubernetes/infrastructure/security/authentik/install/

   cat > myapp-sso-secret.sops.yaml << 'EOF'
   apiVersion: v1
   kind: Secret
   metadata:
     name: myapp-sso-secret
     namespace: authentik
   stringData:
     MYAPP_CLIENT_ID: <generate-uuid>
     MYAPP_CLIENT_SECRET: <generate-secret>
   EOF

   sops -e -i myapp-sso-secret.sops.yaml
   ```

2. **Add to kustomization.yaml**:
   ```yaml
   resources:
     - myapp-sso-secret.sops.yaml
   ```

3. **Add environment variables to helmrelease.yaml** under `ak.environment`:
   ```yaml
   - name: MYAPP_CLIENT_ID
     valueFrom:
       secretKeyRef:
         name: myapp-sso-secret
         key: MYAPP_CLIENT_ID
   - name: MYAPP_CLIENT_SECRET
     valueFrom:
       secretKeyRef:
         name: myapp-sso-secret
         key: MYAPP_CLIENT_SECRET
   ```

4. **Create blueprint** in `blueprint-bootstrap-cm.yaml` (use appropriate number prefix, before 99):
   ```yaml
   75-myapp.yaml: |
     version: 1
     metadata:
       name: myapp-sso
       labels:
         blueprints.goauthentik.io/instantiate: "true"
     entries:
       - model: authentik_core.group
         identifiers:
           name: "MyApp Users"
         attrs:
           users:
             - !Find [authentik_core.user, [username, !Env AK_BLUEPRINT_USER]]

       - model: authentik_providers_oauth2.oauth2provider
         id: myapp-provider
         identifiers:
           name: "MyApp"
         attrs:
           client_id: !Env MYAPP_CLIENT_ID
           client_secret: !Env MYAPP_CLIENT_SECRET
           authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
           invalidation_flow: !Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]
           client_type: confidential
           redirect_uris:
             - url: "https://myapp.lan.${CLUSTER_DOMAIN}/callback"
               matching_mode: strict
           property_mappings:
             - !Find [authentik_providers_oauth2.scopemapping, [scope_name, openid]]
             - !Find [authentik_providers_oauth2.scopemapping, [scope_name, email]]
             - !Find [authentik_providers_oauth2.scopemapping, [scope_name, profile]]

       - model: authentik_core.application
         identifiers:
           slug: "myapp"
         attrs:
           name: "MyApp"
           provider: !KeyOf myapp-provider
           group: "MyCategory"

       - model: authentik_policies.policybinding
         identifiers:
           target: !Find [authentik_core.application, [slug, "myapp"]]
           order: 0
         attrs:
           group: !Find [authentik_core.group, [name, "MyApp Users"]]
   ```

### For Proxy Applications (forward auth)

Same as OAuth2, but use `authentik_providers_proxy.proxyprovider` and **add the provider to the outpost**:

1. Create blueprint with `authentik_providers_proxy.proxyprovider` (number it before 99)

2. **Edit `99-outpost.yaml`** in the blueprint ConfigMap to add the new provider:
   ```yaml
   providers:
     - !Find [authentik_providers_proxy.proxyprovider, [name, "Traefik-Gatekeeper"]]
     - !Find [authentik_providers_proxy.proxyprovider, [name, "Frigate"]]
     - !Find [authentik_providers_proxy.proxyprovider, [name, "MyNewApp"]]  # Add here
   ```

3. Create Traefik middleware in `config/middleware-myapp.yaml`:
   ```yaml
   apiVersion: traefik.io/v1alpha1
   kind: Middleware
   metadata:
     name: authentik-auth-myapp
     namespace: authentik
   spec:
     forwardAuth:
       address: http://ak-outpost-gatekeeper-proxy.authentik.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik
       trustForwardHeader: true
       preserveLocationHeader: true
       authResponseHeaders:
         - X-authentik-username
         - X-authentik-groups
         - X-authentik-email
         - X-authentik-name
         - X-authentik-uid
   ```

4. Create middleware chain in `networking/traefik/config/middlewares/myapp-auth-chain.yaml`:
   ```yaml
   apiVersion: traefik.io/v1alpha1
   kind: Middleware
   metadata:
     name: myapp-auth-chain
     namespace: traefik
   spec:
     chain:
       middlewares:
         - name: default-headers
         - name: authentik-auth-myapp
           namespace: authentik
   ```

5. Reference the middleware chain in your app's ingress:
   ```yaml
   annotations:
     traefik.ingress.kubernetes.io/router.middlewares: myapp-auth-chain@kubernetescrd
   ```

## Scope Mappings

Custom scope mappings can add claims or headers.

### For OAuth2 Providers

```yaml
- model: authentik_providers_oauth2.scopemapping
  id: myapp-roles
  identifiers:
    name: "MyApp Roles"
  attrs:
    scope_name: myapp-roles
    description: "Custom role claims for MyApp"
    expression: |
      roles = []
      if request.user.ak_groups.filter(name="MyApp Admins").exists():
          roles.append("admin")
      return {"roles": roles}
```

### For Proxy Providers (injecting headers)

Use `ak_proxy` structure to inject custom headers:

```yaml
- model: authentik_providers_oauth2.scopemapping
  id: myapp-role-mapping
  identifiers:
    name: "MyApp Role Mapping"
  attrs:
    scope_name: myapp-role
    description: "Maps groups to role header"
    expression: |
      role = "viewer"
      if request.user.ak_groups.filter(name="Admins").exists():
          role = "admin"
      return {
          "ak_proxy": {
              "user_attributes": {
                  "additionalHeaders": {
                      "X-authentik-groups": role
                  }
              }
          }
      }
```

**Note:** Proxy providers need both the default `ak-proxy` mapping AND custom mappings:
```yaml
property_mappings:
  - !Find [authentik_providers_oauth2.scopemapping, [scope_name, "ak-proxy"]]
  - !KeyOf myapp-role-mapping
```

## Environment Variables

Blueprints can reference environment variables:
- `!Env MYAPP_CLIENT_ID` - References key from secrets mounted as env vars
- `${CLUSTER_DOMAIN}` - Flux variable substitution (post-processed)

Environment variables are set in `helmrelease.yaml` under `ak.environment`.
