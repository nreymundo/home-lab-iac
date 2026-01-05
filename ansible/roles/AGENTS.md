# AGENTS.md

**Generated:** 2026-01-05 21:13:08
**Commit:** 9c644bd

## OVERVIEW

Reusable Ansible roles with OS-agnostic abstraction and check-mode safety.
**Key Pattern:** `common` role abstracts Debian/Fedora, roles use `when: not ansible_check_mode`.

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| **OS-agnostic base config** | `common/` | Debian/Fedora abstraction |
| **Proxmox-specific tasks** | `proxmox/` | ZFS tuning, kernel params |
| **VM-specific config** | `vms/` | K3s prep, storage setup |
| **Kernel parameter merging** | `common/tasks/kernel-params.yml` | Safety guards for boot params |

## STRUCTURE

```
ansible/roles/
├── common/                # OS-agnostic base configuration
│   ├── tasks/
│   │   ├── os-debian.yml
│   │   ├── os-fedora.yml
│   │   └── kernel-params.yml
│   └── templates/
├── proxmox/               # Proxmox hypervisor configuration
│   ├── tasks/
│   │   ├── zfs_thin_fix.yml
│   │   └── zfs_thin_audit.yml
│   └── templates/
└── vms/                   # K3s VM configuration
    └── tasks/
        ├── k3s_prep.yml
        └── storage.yml
```

## CONVENTIONS

### OS Abstraction
- **Common role** detects OS family (`ansible_os_family`)
- Abstracts package management: `apt` vs `dnf`
- Abstracts networking: Netplan (Debian) vs NetworkManager (Fedora)

### Check Mode Safety
- Destructive tasks use `when: not ansible_check_mode`
- Safe dry-run: `ansible-playbook ... --check`

### Kernel Parameter Safety
- `common/tasks/kernel-params.yml` implements safe merging
- Blocks modification of boot-critical params: `root=`, `init=`, `resume=`
- Merges baseline parameters with host-specific overrides

### Audit Tasks
- `proxmox/tasks/zfs_thin_audit.yml` registers system state
- Fails gracefully if requirements aren't met

## ANTI-PATTERNS

1. **DO NOT** skip check mode for destructive tasks—use `when: not ansible_check_mode`.
2. **DO NOT** hardcode OS-specific logic—use `os-debian.yml` / `os-fedora.yml`.
3. **NEVER** modify boot-critical kernel parameters without safety guards.

## VERIFICATION

```bash
# Lint role
ansible-lint roles/
# Dry run
ansible-playbook -i inventories/baremetal.yml playbooks/proxmox.yml --check
```

## NOTES

- Pre-commit hook enforces `ansible-lint`.
- Kernel parameter merging uses `combine()` filter with safety checks.
