# Decisions and Trade-offs

This document records the durable rationale behind repository controls,
accepted policy exceptions, and intentionally omitted automation. The source
configuration remains authoritative: this document explains *why*, while the
relevant workflow, hook, or manifest determines *how* a control is enforced.

Update this document when a control, exception, or automation boundary changes.
Keep incident-specific evidence and implementation history in the related issue
or pull request.

## CI and local controls

`CONTRIBUTING.md` is the command reference and `.pre-commit-config.yaml` is the
authoritative local-hook configuration. GitHub Actions CI runs on pull requests,
pushes to `master`, and manual dispatches. Its change detector runs the
applicable jobs for changed paths; the jobs below are hard-failing when they run.

| Control | Where it runs | Purpose and boundary |
| --- | --- | --- |
| YAML syntax, whitespace, line endings, and large-file checks | Local pre-commit | Catch portable formatting and repository-hygiene failures before review. |
| `yamllint` | Local pre-commit | Enforce hand-authored YAML style. Generated Flux bootstrap output and SOPS-encrypted manifests are excluded because they are not normal hand-authored YAML. |
| `ansible-lint` | Local pre-commit for Ansible files | Validate Ansible roles, playbooks, and configuration using the repository Ansible configuration. |
| Packer and Terraform formatting | Local pre-commit for their respective files | Keep HCL canonical and reduce review noise. |
| Sensitive-file and plaintext Kubernetes Secret guards | Local pre-commit | Prevent private key material and unencrypted `kind: Secret` manifests from entering Git. Kubernetes secrets are committed as SOPS-encrypted manifests. |
| SOPS auto-encryption | Local pre-commit for `*.sops.yaml` | Encrypt intended Kubernetes Secret manifests before they are committed. Inspect the resulting diff before committing. |
| Rendered-manifest validation (`kubeconform`) | Local pre-commit and CI for Kubernetes-affecting changes | Render tracked Kustomizations and validate the resulting Kubernetes resources. This is static validation; it does not apply to a cluster. |
| Trivy filesystem scan | Manual local hook and CI for infrastructure/security-relevant changes | Fail on HIGH or CRITICAL vulnerabilities and secrets, ignoring unfixed findings. Generated Flux bootstrap output and `.git` are excluded. |
| Checkov IaC scan | Manual local hook and CI for Kubernetes, Terraform, or Checkov-policy changes | Enforce Terraform and Kubernetes policy checks using `.checkov.yaml`. |
| Commit-message attribution guard | Commit-msg hook | Enforce the repository commit-message policy and forbid attribution trailers. |

The slower Trivy and Checkov hooks are manual locally to keep normal commits
responsive. CI is the shared enforcement point for those scans. CI intentionally
does not replace layer-specific runtime validation or a reviewed live operation.

## Checkov policy exceptions

Checkov scans the `terraform/` and `kubernetes/` trees. Exceptions are narrow by
default: resource-local annotations are preferred over global skips, and each
exception must state its operational reason beside the resource.

### Global configuration boundaries

| Boundary | Reason and compensating control | Revisit when |
| --- | --- | --- |
| `CKV_K8S_43` (image digest pinning) | The homelab accepts version-tag updates instead of digest pinning because digest-only Renovate updates create disproportionate churn. Images are pinned to a specific version, or to a SHA where that is more appropriate. | Image supply-chain requirements change, or digest-update automation becomes low-noise enough to adopt. |
| `kubernetes/clusters/production/flux-system/` | Flux bootstrap output is generated and is not hand-edited. Its source and bootstrap process, rather than generated output, are the review boundary. | The bootstrap ownership model changes. |
| SOPS-encrypted manifests | Checkov does not decrypt secret manifests during static scans. Secret handling is enforced by SOPS, the plaintext-Secret guard, and review of the consuming workload. | A safe, non-secret-leaking encrypted-manifest scanning workflow is adopted. |

### Resource-local exceptions

| Check | Scope | Why it is accepted | Revisit when |
| --- | --- | --- | --- |
| `CKV_K8S_35` (Secret values in environment variables) | Renovate repository token | Renovate expects repository token settings as environment variables. | Renovate supports an equally secure file-backed credential mechanism. |
| `CKV_K8S_35` | Immich auto-stack API key | The upstream job expects its API key as an environment variable. | Immich provides supported file-backed credential input. |
| `CKV_K8S_38` (service-account token) | Paperless backup CronJob | Paperless has no supported external backup interface. The hardened, non-root job needs a token to locate its controller-managed pod and run the supported in-pod export. Its Role is namespace-scoped and limited to `pods` `get`/`list` and `pods/exec` `create`. | Paperless gains a supported external backup interface. |
| `CKV_K8S_38` | PlexTraktSync sync CronJob | The running watcher maintains renewable upstream authentication. A separate job sharing the PVC cannot reliably perform batch sync after authentication expires. Its Role is namespace-scoped and limited to `pods` `get`/`list` and `pods/exec` `create`. | PlexTraktSync supports reliable independent batch authentication. |
| `CKV_K8S_40` (high UID) | Renovate and Immich auto-stack | The upstream images run as UID/GID `1000`; they are already non-root and otherwise hardened. | Upstream images demonstrate compatibility with a higher arbitrary UID. |
| `CKV_K8S_40` | Paperless and PlexTraktSync kubectl jobs | The jobs run explicitly as non-root UID/GID `1001`; the values follow their current job contract. | The kubectl-exec job designs are retired or a compatible higher UID is demonstrated. |
| `CKV_K8S_40` | n8n and Immich database backups | The NFS backup share relies on UID/GID `99:100` ownership mapping. Raising the UID in Kubernetes alone would break backup writes without improving isolation. | The NFS server-side ownership and ACL model is migrated together with the jobs. |

Issue [#676](https://github.com/nreymundo/home-lab-iac/issues/676) records the
hardening work and live-validation evidence that reduced the earlier baseline.

## Terraform pull-request automation

### Decision: do not deploy Atlantis

Terraform roots use Terraform Cloud workspaces for remote state and operations.
Atlantis is intentionally not deployed for this public repository.

Atlantis would add a long-lived service that receives Git hosting webhooks,
holds infrastructure credentials, produces Terraform plan output, and accepts
workflow interactions through pull-request comments. Even with repository
allowlists, branch protection, and command requirements, exposing plans and an
interactive comment-driven control surface in a public repository is not worth
the additional risk or operational burden for this homelab.

The current boundary is deliberate Terraform planning and application through
the established Terraform Cloud workflow, with credentials remaining in the
approved secret-management path. This favors a smaller credentialed attack
surface over pull-request convenience.

Reconsider Atlantis only if the collaboration benefit materially changes and a
separate design demonstrates all of the following:

- a private or otherwise tightly controlled review surface;
- authenticated, restricted webhook ingress;
- least-privileged, isolated Terraform credentials;
- strict repository and command allowlists; and
- explicit review and apply authorization rules.

## Backup assurance

Database backup jobs create PostgreSQL custom-format archives on the NFS backup
share. A successful Job proves authentication and archive creation;
`pg_restore --list` against a read-only NFS mount proves that the archive is
readable without restoring it. Periodic restore drills into a disposable
PostgreSQL instance remain the stronger test of recoverability and should be
performed separately from production.
