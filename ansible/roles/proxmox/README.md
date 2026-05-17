# Proxmox Role

This role manages durable host configuration for Proxmox nodes. It is intended to run through
`ansible/playbooks/proxmox.yml` against the `proxmox` inventory group.

## Responsibilities

- Kernel command-line parameters for systemd-boot and GRUB hosts.
- GPU passthrough module loading, VFIO binding, and driver blacklisting.
- Swapfile creation and swappiness configuration.
- Power tuning through an optional boot-time systemd unit.
- ZFS thin-provisioning audit and optional enforcement.
- ZFS ARC limits.
- Optional CoreFreq DKMS install/removal.
- Root shell profile defaults.

## Important Variables

- `proxmox_kernel_params_base_add` / `proxmox_kernel_params_base_remove`: shared kernel parameters.
- `proxmox_kernel_params_add` / `proxmox_kernel_params_remove`: host-specific kernel parameters.
- `proxmox_gpu_passthrough`: GPU passthrough config. Leave empty to disable.
- `proxmox_gpu_passthrough_cleanup`: remove passthrough files when passthrough is disabled.
- `proxmox_swapfile_path`, `proxmox_swapfile_size`, `proxmox_swapfile_size_bytes`: swapfile settings.
- `proxmox_zfs_thin_pools`: ZFS pools audited for non-thin refreservations.
- `proxmox_zfs_thin_enforce`: set `refreservation=none` for discovered datasets. Enabled for the
  `proxmox` inventory group.
- `proxmox_zfs_arc_min_bytes` / `proxmox_zfs_arc_max_bytes`: ARC module limits.
- `proxmox_power_tuning_enabled`: install and enable the power tuning service.
- `proxmox_power_cpu_governor`, `proxmox_power_cpu_epp`: CPU power policy written at boot.
- `proxmox_power_cpu_boost`: enable or disable CPU boost/turbo at boot.
- `proxmox_power_powertop_auto_tune`: run `powertop --auto-tune` at boot.
- `proxmox_power_tuning_cron_entries_to_remove`: exact root crontab lines removed after migration to
  the systemd unit.
- `proxmox_corefreq_enabled`: install or remove CoreFreq.

## Tags

- `kernel`: kernel command-line management.
- `gpu_passthrough`: VFIO and GPU driver management.
- `storage`: swap and ZFS tasks.
- `swap`: swapfile tasks.
- `zfs`: ZFS audit, enforcement, and ARC tasks.
- `power` / `power_tuning`: power tuning service management.
- `corefreq`: CoreFreq tasks.
- `shell`: root shell profile files.

## Operational Notes

Kernel parameter, module, initramfs, and ZFS ARC changes usually require a reboot to take effect.
Power tuning changes can be applied immediately with:

```bash
systemctl restart proxmox-power-tuning.service
```

Run Ansible from the `ansible/` directory so `ansible.cfg` supplies the expected inventory and role paths:

```bash
ansible-playbook -i inventories/baremetal.yml playbooks/proxmox.yml --limit pve3 --tags power_tuning
```
