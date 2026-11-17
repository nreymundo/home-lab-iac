# NetBird Kubernetes Ingress

**Status: disabled in production.** The production `ks/kustomization.yaml`
excludes `27-netbird-operator-install.yaml` and `28-netbird-config.yaml`, the
operator declares zero replicas, `config/kustomization.yaml` includes no
resources, and Traefik config excludes `service-netbird.yaml`. The shared
NetBird Helm source is still included; that does not deploy the operator.

The retained design uses three `production-ingress` router replicas in
`netbird` and a `traefik-ingress` NetworkResource targeting the
`traefik-netbird` ClusterIP Service in `traefik`. A VPS NetBird Proxy would
target that resource, not individual apps. Re-enabling requires restoring the
operator, router/resource and Service inclusions together with their dependencies.

> [!WARNING]
> The default `All` to `All` policy overrides the restricted ingress policy.
> Replace every required existing connection with explicit policies before
> removing the default policy, or existing NetBird access will break.

For a future re-enable, the retained design requires these NetBird dashboard objects:

1. A dedicated service user PAT with network-management access. Replace
   `NB_API_KEY` in `install/netbird-operator-api-key.sops.yaml` with it using
   `sops`.
2. DNS zone `k3s.netbird.internal`, distributed to `netbird-proxy`.
3. Source group `netbird-proxy` containing the VPS NetBird Proxy peer.
4. Destination group `kubernetes-ingress`.
5. A unidirectional access policy allowing `netbird-proxy` to reach
   `kubernetes-ingress` on TCP port 443.

The `NetworkResource` intentionally targets Traefik instead of an individual
application so NetBird reverse-proxy services retain the existing Kubernetes
Ingress and middleware behavior.
