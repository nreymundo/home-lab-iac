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
- Unraid shared storage NFS mount with systemd automount, including replacing a
  previous CIFS mount at the same mountpoint and removing the legacy retry cron.
- SMTP email notifications through the PVE notification API: endpoint,
  matcher routing, and backup-job notification-mode migration.
- Optional CoreFreq DKMS install/removal.
- Root shell profile defaults.

## Important Variables

- `proxmox_kernel_params_base_add` / `proxmox_kernel_params_base_remove`: shared kernel parameters.
- `proxmox_kernel_params_add` / `proxmox_kernel_params_remove`: host-specific kernel parameters.
- `proxmox_gpu_passthrough`: GPU passthrough config. Leave empty to disable.
- `proxmox_gpu_passthrough_cleanup`: remove passthrough files when passthrough is disabled.
- `proxmox_host_directories`: common directories created on every Proxmox host.
- `proxmox_extra_host_directories`: host-specific directories appended to `proxmox_host_directories`.
- `proxmox_swapfile_path`, `proxmox_swapfile_size`, `proxmox_swapfile_size_bytes`: swapfile settings.
- `proxmox_zfs_thin_pools`: ZFS pools audited for non-thin refreservations.
- `proxmox_zfs_thin_enforce`: set `refreservation=none` for discovered datasets. Enabled for the
  `proxmox` inventory group.
- `proxmox_zfs_arc_min_bytes` / `proxmox_zfs_arc_max_bytes`: ARC module limits.
- `proxmox_install_ai_amd_packages`: install AMD GPU/ROCm/Vulkan host support packages and validate `/dev/kfd`,
  `/dev/dri/renderD128`, and the `amdgpu` kernel module.
- `proxmox_ai_amd_kernel_modules`: kernel modules loaded immediately and at boot when AMD AI/GPU support is enabled.
- `proxmox_ai_amd_required_devices`: device nodes asserted after AMD AI/GPU support is enabled.
- `proxmox_ai_amd_packages`: package list installed when `proxmox_install_ai_amd_packages` is enabled.
- `proxmox_power_tuning_enabled`: install and enable the power tuning service.
- `proxmox_power_cpu_governor`, `proxmox_power_cpu_epp`: CPU power policy written at boot.
- `proxmox_power_cpu_boost`: enable or disable CPU boost/turbo at boot.
- `proxmox_power_powertop_auto_tune`: run `powertop --auto-tune` at boot.
- `proxmox_power_tuning_cron_entries_to_remove`: exact root crontab lines removed after migration to
  the systemd unit.
- `proxmox_corefreq_enabled`: install or remove CoreFreq.
- `proxmox_unraid_nfs_enabled`: master switch for the Unraid NFS storage mount
  (default `false`). The export `/mnt/user/proxmox` is mounted at
  `/mnt/unraid/proxmox` on every node when enabled.
- `proxmox_unraid_nfs_server`, `proxmox_unraid_nfs_export`,
  `proxmox_unraid_nfs_mountpoint`: NFS endpoint and local mountpoint. The
  server defaults to `192.168.10.4`; pve2 overrides it to `10.0.0.2` in
  host_vars for its direct host-only path to the Unraid VM.
- `proxmox_unraid_nfs_options`: list of mount options joined with commas
  (`_netdev,noatime,x-systemd.automount,x-systemd.idle-timeout=600,
  x-systemd.mount-timeout=20s,nofail`), copied from the proven PVE2 mount.
- `proxmox_unraid_nfs_cleanup_legacy`, `proxmox_unraid_nfs_legacy_cron_entries`,
  `proxmox_unraid_nfs_legacy_script_path`: remove the exact root cron lines and
  the `/root/mnt_unraid.sh` retry script left over from the CIFS workaround
  (cleanup defaults to `true`). The separate `/mnt/unraid/backup` mounts on
  pve2/pve3 are not managed by this role and are never modified.
- `proxmox_notifications_enabled`: master switch for email notifications
  (default `false`). Requires `ansible/secrets/proxmox.sops.yml` to be filled
  and encrypted first; see `ansible/secrets/README.md`.
- `proxmox_notifications_secrets_file`, `proxmox_notifications_sops_age_key_file`:
  SOPS secrets file and Age key location (same pattern as the NetBird role).
- `proxmox_smtp_server`, `proxmox_smtp_port`, `proxmox_smtp_mode`: SMTP transport,
  defaulting to `smtp.purelymail.com:587` with STARTTLS.
- `proxmox_smtp_endpoint_name`, `proxmox_smtp_author`: notification endpoint
  name (`infrastructure-email`) and mail author (`Proxmox VE`).
- `proxmox_notifications_matcher_name`, `proxmox_notifications_severities`:
  Ansible-owned matcher to configure (`infrastructure-issues`) and the severities
  it routes (`error`, `warning`, `unknown`; excludes `info` events such as
  successful backups and package-update notices).
- `proxmox_notifications_disable_default_matcher`: disable the built-in matcher
  without replacing its target or filter configuration (default `false`). Enable
  this explicitly when the managed matcher should be the sole notification route.
- `proxmox_notifications_default_matcher_name`: built-in matcher to disable when
  explicitly requested (default `default-matcher`).
- `proxmox_notifications_migrate_backup_jobs`: move backup jobs from
  legacy-sendmail/auto to `notification-system` when notifications are enabled
  (default `false`; old mailto fields are preserved).
- `proxmox_notifications_test_target`: send a test notification on demand
  (default `false`; never sent automatically).

## Tags

- `kernel`: kernel command-line management.
- `gpu_passthrough`: VFIO and GPU driver management.
- `storage`: swap and ZFS tasks.
- `nfs`: Unraid NFS storage mount tasks.
- `swap`: swapfile tasks.
- `zfs`: ZFS audit, enforcement, and ARC tasks.
- `power` / `power_tuning`: power tuning service management.
- `corefreq`: CoreFreq tasks.
- `notifications`: PVE notification system (SMTP endpoint, matcher, backup-job
  migration).
- `shell`: root shell profile files.

## Operational Notes

Kernel parameter, module, initramfs, and ZFS ARC changes usually require a reboot to take effect.

Email notifications are cluster-wide (pmxcfs) and applied once per run through
`pvesh`. Enable them by filling and encrypting `ansible/secrets/proxmox.sops.yml`
and setting `proxmox_notifications_enabled: true` in
`ansible/inventories/group_vars/proxmox.yml`, then apply with:

```bash
ansible-playbook -i inventories/baremetal.yml playbooks/proxmox.yml --tags notifications
```

Rotate the SMTP password in the secrets file and bump
`proxmox_smtp_credential_revision`; the revision is stored in the endpoint
comment and its change triggers a credential update on the next run. A one-off
test mail can be sent with `-e proxmox_notifications_test_target=true`.
Power tuning changes can be applied immediately with:

```bash
systemctl restart proxmox-power-tuning.service
```

Run Ansible from the `ansible/` directory so `ansible.cfg` supplies the expected inventory and role paths:

```bash
ansible-playbook -i inventories/baremetal.yml playbooks/proxmox.yml --limit pve3 --tags power_tuning
```

The Unraid NFS mount replaces any previous CIFS mount at the same mountpoint
after unmounting it; the mount source and fstype are asserted read-only after
the change. On pve2 the NFS server is `10.0.0.2` (host-only path to the Unraid
VM), while pve1/pve3 use `192.168.10.4`; the export, mountpoint, and options
are identical on all nodes.
