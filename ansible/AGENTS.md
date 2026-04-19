# ANSIBLE KNOWLEDGE BASE

## OVERVIEW
`ansible/` configures hosts and the K3s cluster after Terraform creates the VMs.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Main cluster playbook | `playbooks/k3s_cluster.yml` | Applies `common`, `secondary_disk`, and `k3s` roles |
| Other entry playbooks | `playbooks/*.yml` | Proxmox, VMs, upgrades, distro-specific flows |
| Role resolution | `ansible.cfg` | `roles_path = ./roles:./roles/vms` |
| Generated inventory | `inventories/k3s-nodes.yml` | Written by Terraform; not hand-maintained |

## CONVENTIONS
- Inventory defaults live in `ansible.cfg`; run commands from the `ansible/` root or respect that config.
- Generated inventory clearly says it is Terraform-owned.
- Roles are the stable unit of reuse; playbooks stay thin and mostly compose roles.

## ANTI-PATTERNS
- Do not hand-edit `inventories/k3s-nodes.yml`; Terraform overwrites it.
- Do not bypass roles with ad hoc playbook logic when an existing role already owns that concern.

## COMMANDS
```bash
ansible-lint ansible/playbooks/ ansible/roles/
ansible-playbook ansible/playbooks/k3s_cluster.yml --check
```

## NOTES
- Terraform and Ansible are coupled here: node topology and labels originate upstream in `terraform/instances/k3s_nodes`.
