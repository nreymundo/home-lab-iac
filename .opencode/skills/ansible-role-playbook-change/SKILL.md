---
name: ansible-role-playbook-change
description: >-
  Edit Ansible in this repo the right way: role-first design (defaults/vars/
  handlers/tasks/templates), thin playbooks that compose roles, `ansible.cfg`
  execution context (roles_path includes `./roles`, `./roles/containers`,
  `./roles/vms`), Terraform-owned inventory you must not hand-edit, and the
  lint/syntax/check-mode validation chain. Use when the user says "add/change
  an Ansible role or playbook", "configure host X via Ansible", "provision the
  k3s cluster", "fix this ansible-lint failure", or "add a new task/handler/
  template". Pair with `layered-impact-check` when Terraform-driven inventory
  or topology may be the real cause. Do NOT use for Terraform, Packer, or pure
  Kubernetes manifest work.
---

# Ansible Role & Playbook Change

Ansible configures Terraform-provisioned hosts and independently managed
machines, and brings up the K3s cluster. Roles are the durable unit of reuse;
playbooks should stay thin and compose roles.

## When to use

- Add or change a role under `ansible/roles/`.
- Add or change a playbook under `ansible/playbooks/`.
- Add tasks, handlers, defaults, vars, or templates inside an existing role.
- Provision or reconfigure hosts (K3s cluster, LXC, VPS, laptops, Proxmox).
- Fix `ansible-lint` or `--syntax-check` failures.

Pair with `layered-impact-check` when a failure might originate upstream in
Terraform (inventory, labels, hostnames, users). Use
`terraform-infrastructure-change` when the real fix belongs in Terraform.

## Layout

```
ansible/
  ansible.cfg                 # execution contract — roles_path, inventory, etc.
  inventories/                # Terraform-owned; do not hand-edit
    group_vars/
    host_vars/
  playbooks/                  # thin compositions of roles (14 playbooks)
  roles/                      # durable reusable roles (20 roles)
    <role>/{defaults,vars,handlers,tasks,templates}/
  roles/containers/           # additional roles_path entry
  roles/vms/                  # additional roles_path entry
  secrets/                    # Ansible-side secret material
```

Existing roles include `common`, `containers`, `docker`, `fail2ban`, `garage`,
`headless_laptop`, `homebrew`, `k3s`, `llama_swap`, `llm_runtime`,
`lxc_bootstrap`, `lxc_hardening`, `nodejs_runtime`, `openclaw`, `proxmox`,
`ssh_hardening`, `swapfile`, `ufw`, `vms`, `whisper_runtime`.

Existing playbooks: `fedora.yml`, `garage_lxc.yml`, `headless_laptops.yml`,
`k3s_cluster.yml`, `k3s_upgrade.yml`, `llm_lxc.yml`, `netbird.yml`,
`openclaw.yml`, `photon_lxc.yml`, `proxmox.yml`,
`proxmox-fix-thin-provisioning.yml`, `public_vps.yml`, `rpi.yml`,
`ubuntu_vms.yml`.

## Source-of-truth boundaries

- **Roles are the source of truth.** Put durable logic in role `defaults/`,
  `vars/`, `handlers/`, `tasks/`, and `templates/`. Do not scatter one-off
  logic in playbooks when a role already owns that concern.
- **`ansible/inventories/*` is Terraform-owned.** Hand-editing it is an
  anti-pattern; fix the upstream Terraform root instead.
- **`ansible.cfg` is part of the execution contract.** It defines
  `roles_path = ./roles:./roles/containers:./roles/vms`, inventory defaults,
  and SSH pipelining. Commands run outside the `ansible/` root must preserve
  that context explicitly (set `ANSIBLE_CONFIG`).
- **Host topology fixes belong upstream.** If Terraform changes node labels,
  hostnames, or users, verify Ansible assumptions before patching playbooks.

## Workflow

1. Identify whether a role already owns the concern; prefer extending it over
   inventing playbook logic.
2. For a new concern, decide: new role vs. extending a close sibling. Match the
   existing role shape (`defaults/main.yml`, `tasks/main.yml`, etc.).
3. Keep playbooks thin: compose roles, set vars, target hosts from inventory.
4. Use FQCNs (`ansible.builtin.*`), name every task descriptively, and use
   `become: true` only when needed.
5. Put role defaults in `defaults/main.yml`; reserve `vars/` for higher-
   precedence inputs.
6. Run the validation chain below.

## Style (matches `CONTRIBUTING.md`)

- FQCNs everywhere (e.g. `ansible.builtin.apt`).
- Descriptive task `name:` on every task.
- `become: true` only when needed.
- Defaults in `defaults/main.yml`.
- 2-space YAML, explicit `true`/`false`, lines under 120 chars.

## Validation

```bash
# Lint + syntax (read-only; safe to run freely)
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint ansible/playbooks/ ansible/roles/
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/<playbook>.yml --syntax-check

# Against reachable target hosts only (live)
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/<playbook>.yml --check
```

`--check` is a live operation against real hosts — confirm before running. For
routine validation prefer `ansible-lint` and `--syntax-check`.

Pre-commit runs `ansible-lint`; CI does not currently run an Ansible job, so
local validation is the gate (see `.github/workflows/ci.yml`).

## Anti-patterns

- Hand-editing `ansible/inventories/*` (Terraform-owned).
- Bypassing an existing role with ad hoc playbook logic.
- Running commands outside the `ansible/` root without preserving `ansible.cfg`
  via `ANSIBLE_CONFIG`.
- Encoding a topology fix in Ansible when the real source of truth is
  upstream in Terraform.
- Inventing a new role when a sibling already covers the concern.
- Validating with a live `ansible-playbook` run when `--syntax-check` or
  `ansible-lint` answers the question.

## References

- `ansible/AGENTS.md`, repo root `AGENTS.md`
- `CONTRIBUTING.md` Ansible section (style + testing)
- `terraform/AGENTS.md` (upstream inventory ownership)
- `ansible/ansible.cfg` (execution contract)
