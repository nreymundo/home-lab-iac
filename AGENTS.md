# AGENTS.md

This repository is GitOps-first.

## Core rule

If a change can be expressed in the repo, make it in the repo and let Flux reconcile it.

Do not manually patch, apply, edit, scale, restart, or otherwise mutate Kubernetes resources just to "speed things up" or "verify quickly" when the correct path is a GitOps change.

## Default behavior for this repo

- Treat the repository as the single source of truth for cluster state.
- Prefer changing manifests, HelmRelease values, Kustomizations, and supporting config in git.
- Verify with read-only checks first: inspect manifests, Flux objects, events, logs, DNS, ingress status, and rendered state.
- After a repo change, wait for or observe Flux reconciliation instead of applying the same change manually.
- If verification is needed, use non-mutating commands and checks.

## Never do this without explicit user approval

- `kubectl apply`
- `kubectl edit`
- `kubectl patch`
- direct MCP create/update/delete calls against live cluster resources
- manual restarts or scaling of workloads
- any live change that creates drift from git, even temporarily

## Allowed exceptions

Only make direct live changes when the user explicitly asks for a manual or break-glass action, or when there is a clear production emergency and the user has approved an out-of-band fix.

If that happens:

- say clearly that you are leaving the GitOps path
- explain why the live change is necessary
- make the smallest possible change
- immediately follow with the equivalent repo change unless the user says not to

## Operational checklist

Before touching the cluster, ask:

1. Can this be fixed by changing files in this repo?
2. If yes, have I stopped myself from making the same change manually?
3. Can I verify the result through Flux, logs, events, DNS, or HTTP checks without mutating anything?

If the answer to 1 is yes, do not make a live mutation.

## Specific lesson for this repo

When fixing ingress, DNS, Traefik, HelmRelease, or other cluster config issues here:

- change the manifest in git
- wait for Flux to reconcile
- verify outcome read-only

Do not "help" by applying the same manifest directly to the cluster.
