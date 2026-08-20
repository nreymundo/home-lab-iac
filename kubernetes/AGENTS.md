# Kubernetes Agent Notes

Read the repo root `AGENTS.md` first for repo-wide policy. This file only covers Kubernetes-wide rules that apply across the subtree.

## What This Subtree Owns
- Kubernetes manifests become active desired state only through Flux `spec.path` targets and Kustomize resource or component inclusion chains.
- Child AGENTS files under `clusters/production/`, `infrastructure/`, `apps/`, and `components/` own the more specific local editing rules.

## Source Of Truth Boundaries
- Edit hand-authored manifests, not generated Flux bootstrap output.
- Flux `spec.path` targets and parent `kustomization.yaml` files are authoritative inclusion boundaries; file presence alone does not make an object active.
- Shared Helm/OCI source definitions belong in `kubernetes/infrastructure/sources/` unless a child subtree documents a real exception.
- `*.sops.yaml` is the normal committed form for Kubernetes secrets in this repo.

## Editor Schema Metadata
- For new or materially modified custom-resource manifests, add a maintained `yaml-language-server` schema directive when one is available.
- Schema directives are editor-only aids; they do not replace repo validation (`kubectl kustomize` dry-run, kubeconform).
- Do not blanket-annotate manifests or pin static lists of remote schema URLs; omit the directive when no maintained schema exists.

## Kubernetes-Wide Anti-Patterns
- Do not use live reconciliation as validation. Use `kubectl --dry-run=client` or `flux get` first; `flux reconcile` is a live mutation requiring explicit approval.
- Do not hand-edit generated `flux-system` bootstrap output during routine changes.
- Do not scatter new source definitions, secrets, or app wiring outside the subtree that already owns them.

## Validation
```bash
kubectl kustomize <path> | kubectl apply --dry-run=client -f -
flux get all -A
flux get helmreleases -A
```

- Read the closer child AGENTS before editing `clusters/production`, `infrastructure`, `apps`, or `components`; those files should answer the subtree-local gotchas this parent file intentionally omits.
- Treat `flux reconcile kustomization flux-system --with-source` as an intentional live reconciliation of committed state, not local validation.
