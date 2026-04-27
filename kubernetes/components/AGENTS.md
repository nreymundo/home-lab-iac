# Kubernetes Components Agent Notes

Read the repo root `AGENTS.md` and `kubernetes/AGENTS.md` first. This file only covers shared-component rules.

## What This Subtree Owns
- `kubernetes/components/` holds reusable Kustomize building blocks shared by multiple workloads or infrastructure manifests.
- Components are shared inputs, not complete applications or service roots.

## Source Of Truth Boundaries
- A component should own only the reusable fragment it was created for: defaults, shared ingress, shared storage policy, or shared scripts/config.
- Relative component paths are part of the contract because many consumers reference them directly.

## Local Anti-Patterns
- Do not add app-specific business logic to a shared component.
- Do not rename or restructure component paths casually; many downstream kustomizations depend on those relative references.
- Do not assume a component change is local just because only one file changed; inspect downstream consumers first.
- Do not hide breaking changes inside a shared default layer without calling out the blast radius explicitly.

## Validation
- Before editing a shared component, inspect its downstream references in workload and infrastructure manifests.
- Use `kubectl apply --dry-run=client -f <consumer-path>` on one or more representative consumers when the change affects rendered manifests.

## Notes
- Most consumers live under `kubernetes/apps/apps/`, but infrastructure manifests can depend on shared components too.
