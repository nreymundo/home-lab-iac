# KUBERNETES COMPONENTS KNOWLEDGE BASE

## OVERVIEW
`kubernetes/components/` contains reusable Kustomize building blocks shared by multiple apps or infrastructure manifests.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Base app-template defaults | `bjw-s-defaults/` | Shared defaults for many app HelmReleases |
| Shared ingress snippets | `ingress/` | Reusable ingress / Traefik bases |
| Shared storage snippets | `storage/` | Backup-policy and related shared storage pieces |
| Shared scripts/config | `arr-custom-scripts/` | Reusable script payloads for consumers |

## CONVENTIONS
- Components are shared inputs, not full applications.
- Keep component scope narrow and reusable across multiple consumers.
- When changing a component, inspect downstream references before assuming the blast radius is local.

## ANTI-PATTERNS
- Do not add app-specific business logic to a shared component.
- Do not rename or restructure shared component paths casually; many kustomizations reference them relatively.

## NOTES
- Typical consumers live under `kubernetes/apps/apps/`, but infrastructure manifests may also depend on shared components.
