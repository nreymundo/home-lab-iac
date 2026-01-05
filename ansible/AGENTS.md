# AGENTS.md

**Generated:** 2026-01-05 21:13:08
**Commit:** 9c644bd

## OVERVIEW

Ansible configuration management for bare metal hosts and K3s VMs.
**Key Pattern:** OS-agnostic `common` role + dynamic inventory from Terraform.

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| **Configure Raspberry Pi** | `playbooks/rpi.yml` | Edge DNS/VPN nodes |
| **Configure Proxmox hosts** | `playbooks/proxmox.yml` | Hypervisor setup |
| **Configure K3s cluster** | `playbooks/k3s_cluster.yml` | After Terraform provisioning |
| **Role definitions** | `roles/` | Reusable configuration logic |
| **Host/group variables** | `inventories/host_vars/`, `inventories/group_vars/` | Per-host overrides |

## STRUCTURE

```
ansible/
├── playbooks/              # Entry point playbooks
│   ├── rpi.yml
│   ├── proxmox.yml
│   └── k3s_cluster.yml
├── roles/                 # Reusable roles
│   ├── common/            # OS-agnostic base config
│   ├── proxmox/           # Proxmox-specific tasks
│   └── vms/
└── inventories/           # Static and generated inventories
    ├── baremetal.yml      # Physical hosts
    ├── k3s-nodes.yml      # GENERATED - NEVER EDIT
    ├── host_vars/
    └── group_vars/
```

## CONVENTIONS

### Dynamic Inventory
- `k3s-nodes.yml` is **GENERATED** by Terraform—NEVER edit manually
- Must run `terraform apply` before running `ansible-playbook` on K3s nodes

### OS-Agnostic Roles
- **Common role** abstracts Debian (apt) and Fedora (dnf)
- Automatic detection via `ansible_os_family`

### Check Mode Safety
- Destructive tasks use `when: not ansible_check_mode`
- Safe dry-run: `ansible-playbook ... --check`

### Inventory Organization
- `baremetal.yml` = physical hosts (RPi, Proxmox)
- `k3s-nodes.yml` = K3s VMs (Terraform-generated)
- `group_vars/all.yml` = shared configuration

## ANTI-PATTERNS

1. **NEVER** edit `k3s-nodes.yml` manually—use Terraform.
2. **NEVER** make static inventory files executable (`chmod 644`).
3. **DO NOT** hardcode SSH keys—use variables or Bitwarden IDs.
4. **DO NOT** skip `--check` mode for potentially destructive changes.

## VERIFICATION

```bash
# Syntax check
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --syntax-check
# Lint
ansible-lint playbooks/*.yml
# Dry run
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --check
```

## NOTES

- Run from `ansible/` directory to use correct `ansible.cfg` context.
- Pre-commit hook enforces `ansible-lint`.
