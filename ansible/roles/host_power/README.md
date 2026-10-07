# `host_power`

**Unfinished checkpoint:** this role has known execution defects, including an
incorrect RAPL sysfs layout in both helper and fixtures. It is not wired into a
provisioning playbook. The API below describes intent; see the
[checkpoint and blocking fixes](../../../../docs/ubuntu-host-provisioning.md#power-role--initial-scaffold-with-known-defects)
before continuing implementation. Passing fixture tests do not establish real
powercap support.

Reusable Ubuntu 24.04/26.04 host power policy. Apply with the role's `power` tag;
the configuration assertion is also available with `preflight`. The role does
not select a fleet policy: hosts opt in through inventory.

## Public variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `host_power_backend` | `none` | `none`, `sysfs`, or `power-profiles-daemon`. Exactly one policy backend owns CPU power policy. |
| `host_power_profile` | `balanced` | Profile set through `powerprofilesctl` when using PPD (e.g. `power-saver`, `balanced`, `performance`). |
| `host_power_cpu_governor` | `""` | Optional governor applied to every discovered cpufreq policy in sysfs mode. |
| `host_power_cpu_epp` | `""` | Optional energy-performance preference applied to every discovered policy in sysfs mode. |
| `host_power_cpu_boost` | `null` | Optional boolean boost request; Intel `no_turbo` is preferred (inverted), otherwise cpufreq `boost` is used. |
| `host_power_platform_profile` | `""` | Optional sysfs platform profile. Requested choice must be advertised when choices are exposed. |
| `host_power_powertop_auto_tune` | `false` | Install powertop and run its auto-tune command in a separate, persistent unit after the policy unit. |
| `host_power_rapl_limits` | `[]` | Optional list of named, writable RAPL constraints described below. No numeric cap is selected by default. |

PPD cannot be combined with low-level governor, EPP, boost, or platform-profile
requests: those inputs are rejected rather than relying on unverified backend
compatibility. RAPL limits may accompany either selected backend. `none` means
no CPU/RAPL controls; the independent powertop opt-in may still be enabled. It does not disable unrelated policy services. When a
backend is selected, known competing `tuned`, TLP, laptop-mode and (for sysfs)
PPD services are stopped/disabled; adjust `host_power_known_competing_services`
if a host's known controller list differs.

### RAPL list schema

Each list entry must have `zone`, `constraint`, and `power_limit_w`; optional
`time_window_s` sets the matching constraint's time window:

```yaml
host_power_rapl_limits:
  - zone: package-0
    constraint: long_term
    power_limit_w: 45
    time_window_s: 28
```

Zone and constraint names are discovered from powercap sysfs and must each
resolve uniquely. Values are finite positive numbers (booleans are rejected),
converted to kernel microwatts/microseconds. Advertised min/max values are
validated. All requested controls and limits are validated before any sysfs
write. Unsupported, missing, ambiguous, and read-only requests fail explicitly.
The helper reads back effective values; hardware may quantize values, so this
does not promise exact physical enforcement. AMD numeric caps are supported only
when the kernel exposes compatible writable powercap constraints; the role
does not install vendor utilities such as `ryzenadj`.

The helper supports `--check` and `--sysfs-root` for offline fixture use. On
normal runs it only writes drift and reports requested/effective values. Sysfs
files with unset controls are not written. Clearing controls in inventory
stops/removes the managed service and configuration but cannot reliably restore
firmware defaults immediately: reboot to return unmanaged kernel controls to
their platform defaults.

The persistent policy is a oneshot systemd unit ordered after local filesystems
and, for PPD, after the daemon. It is enabled through `WantedBy=multi-user.target`
without ordering *after* that target, avoiding a boot dependency cycle.
Powertop has its own unit and explicitly runs after the policy service. When
disabled, role-owned units/files are stopped/removed; the package need not have
been preinstalled. No power settings are applied to controller OS or live
hosts by local tests.
