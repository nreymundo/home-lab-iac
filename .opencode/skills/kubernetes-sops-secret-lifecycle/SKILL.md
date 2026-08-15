---
name: kubernetes-sops-secret-lifecycle
description: >-
  Safely create, edit, rotate, trace, and validate encrypted Kubernetes SOPS
  Secrets in this repository, including app, infrastructure, cluster, and
  Ansible ownership boundaries, Kustomize inclusion, replication, SOPS MACs,
  and pre-commit auto-encryption. Never expose secret values. Do not use this
  for an undocumented Age-recipient or `.sops.yaml` rule migration.
---

# Kubernetes SOPS Secret Lifecycle

Use this skill for the repository lifecycle of an encrypted secret. It is a
source-of-truth and reference-tracing workflow, not a reason to patch a live
Secret or print decrypted data. Read the root and nearest subtree `AGENTS.md`
files first. Preserve unrelated work already present in the working tree.

## Ownership boundaries

Choose the owner before choosing a filename:

| Secret concern | Source-of-truth boundary | Normal consumer path |
| --- | --- | --- |
| Workload-owned value, database credential, API key, or session secret | `kubernetes/apps/apps/<category>/<app>/` | That app's HelmRelease, Job, or mounted volume; list the file in the app Kustomization. |
| Shared infrastructure-service credential | `kubernetes/infrastructure/<domain>/<service>/install/` or `config/` beside the service | The service's install/config manifests and their owning Flux Kustomization. |
| Cluster identity or cluster-wide bootstrap secret | `kubernetes/clusters/production/identity/` or the documented cluster bootstrap owner | Cluster Kustomizations, usually through SOPS decryption and post-build substitution. |
| Ansible-only secret | `ansible/secrets/` | Ansible roles/playbooks only; the Ansible SOPS rule encrypts the complete document. Do not move it into Kubernetes because both use SOPS. |

Do not put a secret in the nearest convenient directory. For a shared Authentik
native-OIDC client, the Authentik-side `<app>-sso-secret` owns the credentials
and the replicator delivers the named Secret to the workload namespace; the
workload must not create a second credential copy. For a local app session
secret or API key, keep the source beside the app that owns it.

## Trace the complete contract before editing

For every create, edit, or rotation, record the following without recording any
value:

1. source file, Secret name, namespace, type, and cleartext key names;
2. the owning Kustomization and Flux `spec.path` that make the file active;
3. every consumer reference (`secretKeyRef`, `envFrom`, projected volume,
   `secretName`, Job, Helm value, or Ansible variable);
4. namespace delivery: direct same-namespace use, Kustomize namespace transform,
   kube-replicator annotation, or another explicitly documented mechanism;
5. rollout/reload behavior and any dependency ordering that must be preserved.

Use repository search and reads to trace names and keys. A file being present
under a directory does not make it active. In particular:

- workload resources are included by the app Kustomization and then by
  `kubernetes/apps/production/kustomization.yaml`, which is reconciled as
  `apps-manifests` with `prune: true`;
- infrastructure install/config resources are included by their local
  Kustomization and then by a numbered Flux Kustomization under
  `kubernetes/clusters/production/ks/`;
- `apps-manifests` currently depends on `apps-storage` and `traefik-config`;
  Authentik install/config and kube-replicator have their own `dependsOn`
  contracts. Inspect the actual manifests rather than inferring order from
  filenames;
- a replicated Secret's contract is source Secret → `replicate-to` annotation
  → kube-replicator → consumer-namespace replica → consumer reference. Do not
  replace that with a copied workload-local credential.

If the source and consumer disagree on namespace, Secret name, key name, or
delivery mechanism, stop and fix the source contract rather than adding a
second secret.

## Repository `.sops.yaml` rules

The current root rules are part of the encryption contract and must not be
edited as part of routine secret work:

```yaml
creation_rules:
  - path_regex: ^ansible/secrets/.*\.sops\.ya?ml$
    encrypted_regex: '.*'
    age: <repository recipient>
  - path_regex: .*\.sops\.ya?ml$
    encrypted_regex: '^(data|stringData)$'
    age: <repository recipient>
```

The first rule is for Ansible secrets and encrypts every field. The general rule
is for SOPS YAML files, including Kubernetes Secrets, and encrypts `data` and
`stringData`; API metadata and resource structure remain visible so Kubernetes
can identify the object. Never copy an Age private key into the repository or
put a Kubernetes value in a non-SOPS manifest.

Do not alter `.sops.yaml`, its recipient, or its rules during normal create,
edit, or rotation work. A recipient or rule change is a repository-wide key
management event, not a secret edit.

## Safe create

1. Choose the owner, name, namespace, key names, and owning Kustomization from
   an exact sibling.
2. Create only the structural manifest needed by that owner. Keep values out
   of shell arguments, command history, chat, logs, and Git diffs.
3. Use the SOPS editor workflow (`sops edit <new-or-existing-file>`) to enter
   values directly into the protected editing buffer, or use the repository's
   approved protected-input method. Do not use `kubectl create secret` output,
   `--from-literal`, a heredoc containing credentials, or an unencrypted file
   as a committed intermediate.
4. If a tool requires a temporary plaintext representation, use a mode-0600
   temporary file on protected local storage, never stage it, encrypt the
   complete document immediately through the root creation rule, remove it in
   a trap, and verify that no plaintext copy remains. Prefer `sops edit` so the
   normal workflow owns the encryption and MAC update.
5. Confirm that the resulting tracked file has a `sops` stanza and that only
   the intended Secret structure, key names, and metadata are present. Do not
   print the file after encryption if the command could reveal input or editor
   state.
6. Add the file to its owning Kustomization. Do not add a workload-local copy
   when a shared/replicated source contract already exists.

The filename must normally end in `.sops.yaml` or `.sops.yml` so the root rule,
pre-commit hook, and repository policy recognize it. A plaintext Kubernetes
`kind: Secret` is never an acceptable source-of-truth artifact.

## Safe edit and rotation

Use `sops edit <file>` for both metadata and encrypted value changes. SOPS must
rewrite the complete document and recalculate the MAC. Do not use `sed`, a YAML
formatter, a merge tool, or a patch against an encrypted file—even for an
apparently harmless annotation, namespace, key rename, or timestamp.

Before a rotation:

- identify every consumer and whether it reads the old key name or Secret name;
- decide whether the application supports overlapping old/new credentials or
  requires a coordinated rollout;
- for a replicated source, rotate the source once and let the established
  replicator contract deliver it; do not rotate a replica as if it were an
  independent source;
- preserve the Secret name, namespace, key names, replication annotations, and
  Kustomization inclusion unless the consumer migration explicitly changes
  them;
- plan the app or infrastructure reload and the safe point at which the old
  credential is revoked in the upstream system;
- inspect staged and unstaged diffs after SOPS rewrites the document, checking
  that no unrelated secret or user work was touched.

For a Secret name or key rename, update the source and every consumer in one
source-of-truth change and trace the complete Kustomize/Flux path again. Do not
leave a second value behind as a speculative fallback.

## SOPS MAC behavior

SOPS authenticates the encrypted values and the selected cleartext document
fields with a MAC. Kubernetes metadata such as `namespace`, annotations, and
the encrypted-field selection is therefore not safe to hand-edit outside SOPS:
the file can look structurally valid while its MAC is invalid. `sops edit`
re-encrypts the full document and updates the MAC; it is the required path for
any data or metadata change.

If a SOPS integrity check fails, do not remove the `sops` stanza, delete the
MAC, copy ciphertext from another file, or decrypt and re-encrypt ad hoc with a
different recipient. Restore the source through the approved SOPS workflow and
ask the parent orchestrator when the original recipient or file state is not
available.

## Age recipient changes: high-risk and undocumented

There is no routine, repository-local procedure documented here for changing an
Age recipient. Treat an Age recipient change or a `.sops.yaml` rule change as a
**high-risk, undocumented key-management operation**:

- stop normal secret work and obtain explicit owner approval;
- do not edit `.sops.yaml`, run a bulk re-encryption, or rotate the Flux
  `sops-age` key as an improvised fix;
- require a separately reviewed migration procedure covering the complete
  affected inventory, old-key availability, new-key distribution, Flux,
  Ansible, rollback, and non-disclosing verification;
- do not claim that an individual Secret rotation is complete while the
  recipient migration is unresolved.

This skill intentionally does not invent that missing procedure. The normal
secret lifecycle resumes only after the owner supplies and approves it.

## Pre-commit encryption and staging

The repository's `sops-auto-encrypt` hook runs for changed `*.sops.yaml` and
`*.sops.yml` files except the root `.sops.yaml`. It skips a file that already
contains a `sops:` stanza; otherwise it runs SOPS in place and stages the file
with `git add`. This means the hook can change both the worktree and the index.

Run the applicable hook only on intended paths:

```bash
pre-commit run --files <changed-secret> [<other-intended-file>...]
```

Then inspect both views:

```bash
git status --short
git diff -- <intended-paths>
git diff --cached -- <intended-paths>
```

Do not reset, restore, or unstage unrelated pre-existing work. If a hook stages
an unintended path or produces a plaintext artifact, stop, remove only the
known temporary artifact safely, and report the state to the parent
orchestrator. Review the complete staged diff before commit; a successful hook
is not proof that the ownership or consumer contract is correct.

## Non-disclosing validation

Validation must establish encryption, structure, inclusion, and references
without displaying secret values:

- inspect `git status`, `git diff --name-only`, and redacted/metadata-only diffs;
- verify the file is named `*.sops.yaml`/`*.sops.yml`, contains a SOPS stanza,
  and is included by the owning Kustomization;
- run the relevant `kubectl kustomize ... >/dev/null` commands and
  `pre-commit run --files ...`; never redirect a rendered Secret to a file for
  inspection;
- where an integrity check is authorized, use
  `sops --decrypt <file> >/dev/null` (or an equivalent output-to-`/dev/null`
  form) and never send decrypted output to a terminal, log, artifact, or
  `kubectl apply` input. If the task forbids decryption, skip this check and
  report it as skipped;
- use `kubectl get secret <name> -n <namespace> -o name` or metadata-only
  queries for live existence checks. Never use `kubectl get secret -o yaml`,
  `jsonpath` for a value, `base64 --decode`, `printenv`, or pod logs to inspect
  Secret data;
- verify consumer references by source text and rendered object names, not by
  dumping live Secret contents;
- treat a successful Kustomize render as structural evidence only. It does not
  prove decryption, replication, application reload, or login success.

Never paste secret values into a plan, issue, commit message, test output, or
final report. Report only paths, object names, namespaces, key names, and
pass/fail status.

## Stop conditions

Stop and ask the parent orchestrator when ownership is ambiguous, a consumer
expects a different Secret contract, a plaintext Secret was created, SOPS MAC
verification fails, a recipient/rule change is proposed, or validation would
require exposing or decrypting a value contrary to the task constraints.
