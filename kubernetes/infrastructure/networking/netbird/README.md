# NetBird Kubernetes Ingress

The NetBird operator publishes the existing Traefik `ClusterIP` Service through
an HA pool of in-cluster NetBird routing peers. The VPS NetBird Proxy can then
target this resource for public reverse-proxy services.

> [!WARNING]
> The default `All` to `All` policy overrides the restricted ingress policy.
> Replace every required existing connection with explicit policies before
> removing the default policy, or existing NetBird access will break.

Before Flux can reconcile the configuration, create these NetBird dashboard
objects:

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
