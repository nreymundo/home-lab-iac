# LXC Bootstrap Role

Runs a basic container bootstrap for Debian/Ubuntu and Fedora/RedHat LXCs.

The role performs a full package upgrade by default, then installs a small
baseline package set for interactive administration and troubleshooting. Use
`lxc_bootstrap_extra_packages` from inventory or host vars to add
workload-specific packages without changing the role defaults.

The role also manages scheduled automatic updates: unattended-upgrades on
Debian/Ubuntu and dnf-automatic with a timer drop-in on Fedora/RedHat. Control
this with `lxc_bootstrap_enable_unattended_upgrades`,
`lxc_bootstrap_unattended_upgrades_auto_reboot`, and
`lxc_bootstrap_unattended_upgrades_reboot_time`.

Beyond that, it intentionally avoids full-system configuration such as kernel
arguments, users, networking, firewalling, or application setup.
