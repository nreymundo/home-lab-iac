# LXC Bootstrap Role

Runs a basic container bootstrap for Debian/Ubuntu and Fedora/RedHat LXCs.

The role performs a full package upgrade by default, then installs a small
baseline package set for interactive administration and troubleshooting. Use
`lxc_bootstrap_extra_packages` from inventory or host vars to add
workload-specific packages without changing the role defaults.

This role intentionally avoids full-system configuration such as timers, kernel
arguments, users, networking, firewalling, or application setup.
