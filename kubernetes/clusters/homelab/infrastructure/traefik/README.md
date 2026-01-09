> **DEPRECATED:** Traefik has migrated to `kubernetes/platform/base/ingress/traefik/`. This directory is no longer authoritative.

# Traefik Ingress Controller

Traefik is the router for the cluster. It handles:
- **Ingress:** HTTP/HTTPS traffic entering the cluster.
- **SSL:** Automatic TLS termination (via cert-manager).
- **Middlewares:** Auth, IP whitelisting.

## Configuration

Traefik is configured via Helm values in `install/helmrelease.yaml` and dynamic config in `config/`.

### Key Features

1.  **Global HTTP -> HTTPS Redirect**
    - Port 80 is open but redirects everything to 443.

2.  **Dashboard**
    - Accessible at `traefik.lan.<DOMAIN>`
    - Protected by Basic Auth (admin user).

3.  **Metrics**
    - Exposes Prometheus metrics on port 9100.
    - Scraped by Prometheus ServiceMonitor.

## Middlewares

We use middlewares to enforce security policies.

### 1. LAN Allowlist (`lan-allowlist`)
Restricts access to local network ranges only.
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: lan-allowlist
spec:
  ipAllowList:
    sourceRange:
      - 192.168.0.0/16
```

### 2. Authentik Auth (`authentik`)
Forces users to log in via SSO before accessing the app.
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik
spec:
  forwardAuth:
    address: http://ak-outpost-internal-auth-outpost.authentik.svc.cluster.local:9000...
```

## How to Expose an App

### Method 1: Standard Ingress (Recommended)
Use this for simple HTTP/HTTPS apps.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    # Use Traefik
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    # Apply middlewares
    traefik.ingress.kubernetes.io/router.middlewares: traefik-lan-allowlist@kubernetescrd
spec:
  rules:
    - host: myapp.lan.example.com
      http:
        paths: ...
```

### Method 2: IngressRoute (Advanced)
Use this for TCP/UDP or advanced routing rules.

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.lan.example.com`)
      kind: Rule
      services:
        - name: myapp
          port: 80
      middlewares:
        - name: lan-allowlist
          namespace: traefik
```

## Troubleshooting

- **404 Not Found:** Traefik doesn't have a router for that host/path. Check `kubectl get ingress`.
- **403 Forbidden:** Blocked by middleware (Allowlist) or Auth failed.
- **Certificate Error:** Cert-manager didn't issue the cert. Check `kubectl get certificates`.
