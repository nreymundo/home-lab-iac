# Traefik Ingress Controller

Traefik is the router for the cluster. It handles:
- **Ingress:** HTTP/HTTPS traffic entering the cluster.
- **SSL:** Automatic TLS termination (via cert-manager).
- **Middlewares:** Auth, IP whitelisting.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     cert-manager                             │
│                         (Wildcard cert)                           │
│                              │                                    │
│                              │ Replicator                        │
│                              │                                    │
│                              ▼                                    │
│  kubernetes-replicator    ──────►  ingress namespace            │
│                                                          │
│                              ▼                                      │
│                          Traefik (app + CRDs)                     │
│                               │                                        │
│                               │ ┌──────────────────────┐          │
│                               ▼ │                      │          │
│                     services namespace  │                      │          │
│                          │  (Middlewares)   │          │
│                          └──────────────────────┘          │
│                                                          │
│                       ┌─────────────┬─────────────┐        │
│                       │             │             │        │
│                       ▼             ▼             ▼        │
│                   Apps   External Services   Monitoring       │
└─────────────────────────────────────────────────────────────────────┘
```

## Configuration

Traefik is configured via Helm values and dynamic CRDs.

### Middlewares

Located in `kubernetes/core/base/services/traefik-middlewares/` (namespace `services`):

**1. LAN Allowlist (`services-lan-allowlist`)**
Restricts access to local network ranges only.
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: lan-allowlist
  namespace: services
spec:
  ipAllowList:
    sourceRange:
      - 192.168.0.0/16
      - 10.1.20.0/27
```

**2. Authentik Auth (`services-authentik-forwardauth`)**
Forces users to log in via SSO before accessing the app.
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik-forwardauth
  namespace: services
spec:
  forwardAuth:
    address: http://ak-outpost-internal-auth-outpost.authentik.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik
```

**3. LAN HTTPS Insecure (`services-lan-https-insecure`)**
Allows Traefik to skip certificate verification when talking to internal HTTPS backends.
```yaml
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: lan-https-insecure
  namespace: services
spec:
  insecureSkipVerify: true
```

## How to Expose an App

### Method 1: Standard Ingress (Recommended)
Use this for simple HTTP/HTTPS apps.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.middlewares: >-
      services-lan-allowlist@kubernetescrd,
      services-authentik-forwardauth@kubernetescrd
 spec:
  ingressClassName: traefik
  rules:
    - host: myapp.lan.${DOMAIN_NAME}
      http:
        paths: ...
```

### Method 2: IngressRoute (Advanced)
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.lan.${DOMAIN_NAME}`)
      services:
        - name: myapp
      middlewares:
        - name: lan-allowlist
          namespace: services
        - name: authentik-forwardauth
          namespace: services
```

## Troubleshooting

- **404 Not Found:** Traefik doesn't have a router for that host/path. Check `kubectl get ingress`.
- **403 Forbidden:** Blocked by middleware (Allowlist) or Auth failed.
- **Certificate Error:** Cert-manager didn't issue the cert. Check `kubectl get certificates`.
