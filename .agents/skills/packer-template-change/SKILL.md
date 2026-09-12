---
name: packer-template-change
description: >-
  Safely validate or change this repository's Packer base-image and VM template
  workflow, including autoinstall inputs, template-local wrappers, shared
  Packer scripts, and Packer build failures. Use when the user mentions a base
  image, Packer template, autoinstall change, or a failed Packer build. Discover
  template roots dynamically, trace Terraform consumers and downstream Ansible
  assumptions, and require explicit approval before any live image build. Do
  NOT use for pure Terraform infrastructure changes, general Ansible changes,
  or Kubernetes manifest work.
---

# Packer Template Change

Packer template directories are self-contained build roots, but a base image is
not an isolated artifact: Terraform may clone it and Ansible may depend on the
OS, users, packages, disks, network names, or cloud-init behavior it provides.
Validate the source workflow first and follow those consumers before declaring a
template change safe.

## When to use

- Editing a Packer base-image or VM template, its variables, provisioners, or
  source configuration.
- Changing an autoinstall/cloud-init file or the generator that produces one.
- Changing a template-local `build.sh`, Make target, helper, or a shared script
  under `packer/scripts/`.
- Investigating `packer validate`, plugin, provisioning, or image-build
  failures.
- Checking the downstream effect of changing the OS family, image contents,
  template identifier, disk layout, user, SSH setup, or installed tooling.

Do not use it as a substitute for `terraform-infrastructure-change` when the
source-of-truth change is Terraform, or for `ansible-role-playbook-change` when
the source-of-truth change is an Ansible role/playbook. Pair with
`layered-impact-check` when the change crosses those layers.

## Discover roots; never maintain a template allowlist

Do not hard-code the repository's current template directory names. Discover
roots from the checkout and from the changed path at execution time. A useful
starting point is the directory of each tracked `*.pkr.hcl` file under
`packer/`, deduplicated and then checked for local wrappers and inputs:

```bash
find packer -type f -name '*.pkr.hcl' -printf '%h\n' | sort -u
```

Also inspect a changed file's ancestors and any wrapper-defined root; a root may
prepare files outside the HCL directory. Do not treat `packer/scripts/` as a
template root merely because it contains shared helper code.

## Source-of-truth pass

1. Read the repository `AGENTS.md`, `packer/AGENTS.md`, and the nearest
   applicable `AGENTS.md` for every changed path. Record the owning template
   root or shared-script boundary before editing.
2. Inspect all files in each discovered root: `*.pkr.hcl`, variable files,
   `build.sh` or other wrappers, autoinstall/cloud-init inputs, README or Make
   instructions, and local helper scripts. Read `packer/scripts/` references
   when a template calls shared logic.
3. Respect wrappers. If a wrapper generates an autoinstall file, answer-file,
   checksum, or other input required for a correct build, use its documented
   preparation/validation path rather than bypassing it with a direct Packer
   command. Generated inputs are workflow artifacts: fix the generator or
   source template, not a generated output by guesswork. Do not invent wrapper
   flags; inspect the script and its documented modes first.
4. If a shared script changes, search every template root that references it
   and validate each affected root. If the change is template-local, keep the
   edit local and still check downstream consumers of that template.

## Trace Terraform template consumers

Extract the changed template's actual identifiers, source image metadata, output
names, and clone-related values from its HCL and search for those exact values
and references under `terraform/`. Inspect every matching Terraform root and
read `terraform/AGENTS.md` before deciding the impact. Follow the complete path
through modules, `source`/clone resources, variables, and outputs; do not stop at
the first textual match.

For each consumer, check whether the change affects:

- the template/image identifier or clone source;
- disk size, bus, filesystem, storage controller, or boot mode;
- OS family/version, cloud-init completion, qemu guest agent, or package
  availability;
- the default user, SSH keys, sudo policy, hostname, or network interface;
- kernel/modules, container runtime prerequisites, or time/identity setup.

Do not hand-edit Terraform-generated Ansible inventory. If Terraform output
changes, inspect the generated inventory diff and continue to the Ansible
assumptions it feeds.

## Trace downstream Ansible assumptions

Read `ansible/AGENTS.md` and the relevant inventory, `group_vars/`, `host_vars/`,
roles, and playbooks. Check assumptions that the new image must satisfy,
including OS-family package modules, Python availability, SSH and become users,
service names, package repositories, mount/device names, network interface
names, cloud-init ordering, and K3s/container prerequisites. If a build failure
or post-build failure suggests a missing OS contract, verify the Packer and
Terraform sources before adding a compensating Ansible task.

When an inventory file carries the Terraform-generated header, treat it as
output and fix the upstream Terraform or Packer contract. Only hand-maintained
inventories and Ansible-owned variables/roles are direct edit surfaces.

## Build-failure triage

Capture the discovered root and exact failing command, then classify the failure
before changing files:

1. **Initialization/plugin:** inspect the root's required plugins and run
   `packer init` for that root.
2. **Formatting/validation:** inspect HCL syntax, variables, source/plugin
   arguments, and wrapper-generated inputs.
3. **Provisioning:** identify the failing provisioner and its referenced script,
   package repository, user, path, or generated answer file. Check shared-script
   consumers before changing a shared helper.
4. **Post-build consumer:** compare the resulting image contract with Terraform
   clone settings and Ansible assumptions; do not treat a downstream symptom as
   proof that Packer is the only owner.

Avoid repeated builds as a debugging method. A wrapper that performs generation
and a build is not a harmless validation command; inspect it and use only a
non-build preparation mode unless the live build has been approved.

## Read-only validation

Run the required checks for every affected, dynamically discovered template
root. If a wrapper prepares required generated inputs, perform that preparation
according to its documented workflow before validation:

```bash
packer init <template-root>
packer fmt -check -recursive <template-root>
packer validate <template-root>
```

Run file-scoped repository hooks for the source changes and any hand-authored
inputs they affect:

```bash
pre-commit run --files <changed-file> [<additional-changed-file>...]
```

When a Terraform consumer's contract is affected, run its root's read-only
`terraform init`, `terraform fmt -check`, and `terraform validate`; inspect
generated inventory output without editing it. When Ansible assumptions are
affected, run the relevant `ansible-lint` and playbook `--syntax-check` checks
with `ANSIBLE_CONFIG=ansible/ansible.cfg`. Terraform `plan`, Ansible `--check`,
and any host/image operation require their own explicit live-operations approval
and are not implied by Packer validation.

## Explicit live-build boundary

`packer build` creates or mutates an external image and is never an automatic
validation step. Require explicit user approval for the exact template root,
wrapper/command, variables, target, and expected side effects. After approval,
use the template's documented wrapper when one owns generation or build order;
do not bypass it with an ad hoc direct build. Without approval, stop after
initialization, formatting, validation, dependency tracing, and a report of
the expected downstream impact.

## Expected report

Return the dynamically discovered root(s), nearest `AGENTS.md` ownership,
wrapper/generated-input boundary, shared-script consumers, Packer validation
results, Terraform template consumers, downstream Ansible assumptions, and any
requested live build that remains blocked pending approval. Never report a
hard-coded current template list as the discovery mechanism.

## References

- `AGENTS.md`, `packer/AGENTS.md`, `terraform/AGENTS.md`, and `ansible/AGENTS.md`
- `CONTRIBUTING.md` Packer, Terraform, and Ansible testing sections
- `terraform-infrastructure-change`, `ansible-role-playbook-change`, and
  `layered-impact-check` for adjacent owned workflows
