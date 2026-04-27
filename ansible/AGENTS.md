# Ansible Agent Notes

Read the repo root `AGENTS.md` first for repo-wide policy. This file only covers Ansible-local editing rules.

## What This Subtree Owns
- `ansible/` is responsible for host and cluster configuration after Terraform has provisioned infrastructure.
- Roles are the durable unit of reuse; playbooks should stay thin and primarily compose roles.
- `ansible.cfg` is part of the execution contract because it defines role paths, inventory defaults, and command expectations.

## Source Of Truth Boundaries
- Treat generated inventory such as `ansible/inventories/k3s-nodes.yml` as Terraform-owned output.
- Treat role defaults, vars, handlers, and tasks as the source of truth instead of scattering one-off playbook logic.
- If Terraform changes node labels, hostnames, or users, verify Ansible assumptions before changing the playbooks to compensate.

## Local Anti-Patterns
- Do not hand-edit Terraform-generated inventory.
- Do not bypass an existing role with ad hoc playbook logic when that concern already has a stable owner.
- Do not assume commands run the same way outside the `ansible/` root unless you preserve the `ansible.cfg` context explicitly.
- Do not encode infrastructure-topology fixes in Ansible when the real source of truth lives upstream in Terraform.

## Validation
```bash
ansible-lint ansible/playbooks/ ansible/roles/
ansible-playbook ansible/playbooks/k3s_cluster.yml --check
```

- Treat the playbook command above as a representative example; for subtree-local validation, run the specific playbook(s) you modified with `--check` when possible.
- After Terraform-driven inventory or topology changes, re-check host grouping, labels, and any role assumptions before treating Ansible failures as purely local bugs.
