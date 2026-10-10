# `host_power`

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
| `host_power_cpu_max_freq_khz` | `null` | Optional positive integer kHz ceiling for cpufreq policies whose `cpuinfo_max_freq` is strictly greater than the requested value. Sysfs mode only. |
| `host_power_platform_profile` | `""` | Optional sysfs platform profile. Requested choice must be advertised when choices are exposed. |
| `host_power_powertop_auto_tune` | `false` | Install powertop and run its auto-tune command in a separate, persistent unit after the policy unit. |
| `host_power_rapl_limits` | `[]` | Optional list of named, writable flat-ABI RAPL constraints described below. No numeric cap is selected by default. |

PPD cannot be combined with low-level governor, EPP, boost, CPU maximum-frequency ceiling, or platform-profile
requests: those inputs are rejected rather than relying on unverified backend
compatibility. RAPL limits may accompany either selected backend. `none` means
no CPU/RAPL controls, including the CPU frequency ceiling; the independent powertop opt-in may still be enabled. It does not disable unrelated policy services. Previously managed PPD is stopped when relinquished. When a
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
normal runs it only writes drift and reports requested/effective values plus a
`changed` flag. Every normal Ansible run invokes it, including unchanged active
oneshots. Quantized readback differing from the request can cause a repeat write. Sysfs
files with unset controls are not written. Clearing controls in inventory
stops/removes the managed service and configuration but cannot reliably restore
firmware defaults immediately: reboot to return unmanaged kernel controls to
their platform defaults.

The optional CPU maximum-frequency ceiling uses the Linux cpufreq policy ABI:
the requested kHz value must be a finite positive integer, and must be at least
the selected policy's `scaling_min_freq`. A policy is selected only when its
`cpuinfo_max_freq` is strictly greater than the ceiling; equal-or-lower policies
are left completely untouched by this control. All selected policy controls are
validated before writes, and boost (when requested) is applied before the
ceiling because boost changes can reset policy limits. Linux may clamp the
requested value, so the helper preserves strict readback checks. After writing
`scaling_max_freq`, the helper allows up to 20 additional reads at 50 ms intervals
for a delayed exact readback (about one second total); a persistent mismatch still
fails. This bounded wait is only for a changed frequency ceiling—not for an
already-correct value, check mode, or other controls. A value of
`4200000` kHz is an exact 100 MHz step commonly used for an Intel P-core limit,
but this threshold is not core-type detection and does not guarantee that only
P-cores (or any particular core class on other CPUs) are selected. Inspect the
host's actual policy maxima before opting in.

The persistent policy is a oneshot systemd unit ordered after local filesystems
and, for PPD, after the daemon. It is enabled through `WantedBy=multi-user.target`
without ordering *after* that target, avoiding a boot dependency cycle.
Powertop has its own unit and explicitly runs after the policy service. When
disabled, role-owned units/files are stopped/removed; the package need not have
been preinstalled. No power settings are applied to controller OS or live
hosts by local tests.
