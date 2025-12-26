# Authentik Manual Setup

This directory contains the Helm-based installation of Authentik. Some components require manual configuration through the Authentik UI after deployment.

## Initial Setup

1. **Access Initial Setup URL**
   - After the first deployment, access the setup URL to create the admin account
   - Follow the web-based setup wizard

2. **Create Admin Account**
   - Set your admin username and password
   - Complete the initial configuration

## Application & Provider Configuration

1. **Create a New Application**
   - Navigate to: Applications → Applications → Create
   - Type: Choose based on your needs (e.g., OAuth2 / OIDC Provider, or Proxy Provider)
   - Configure the application settings
   - Set appropriate callback URLs

2. **Configure Provider Settings**
   - Link the provider to your application
   - Set authentication flow and authorization settings as needed

## Outpost Configuration

The outpost is used for forward authentication with Traefik.

1. **Create a New Outpost**
   - Navigate to: Applications → Outposts → Create
   - **Type**: Proxy
   - **Provider**: Select the Proxy Provider created above
   - **Name**: Choose a name (e.g., `internal-auth-outpost`)

2. **Configure Outpost Settings**
   - **Authentik Host**: Use the internal Kubernetes service URL
     - `http://authentik-server.authentik.svc.cluster.local`
   - **Authentik Web URL**: Use the public-facing domain
     - Current: `https://auth.lan.${DOMAIN_NAME}`
     - Future (after removing lan. subdomain): `https://auth.${DOMAIN_NAME}`

## Integration Notes

- The outpost is currently managed manually through the Authentik UI
- The Traefik middleware (`../../traefik/config/authentik-middleware.yaml`) references the outpost service directly
- Outpost service name format: `ak-outpost-<outpost-name>`
- If you rename the outpost in the UI, update the middleware configuration accordingly

## Current Configuration

- **Ingress**: `config/ingress.yaml`
  - Host: `auth.lan.${DOMAIN_NAME}`
  - Entry point: `websecure`
  - Middleware: `traefik-lan-allowlist@kubernetescrd`

- **Database**: CloudNative-PG managed PostgreSQL
  - Cluster name: `authentik-db`
  - Service: `authentik-db-rw.authentik.svc.cluster.local`

- **Helm Values**: `install/helmrelease.yaml`
  - Server replicas: 1
  - Worker replicas: 1
