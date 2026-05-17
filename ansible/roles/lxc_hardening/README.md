# LXC Hardening Role

Applies a minimal baseline for Linux containers without running the broader
full-system `common` role.

The role supports Debian/Ubuntu and Fedora/RedHat containers. It intentionally
limits scope to SSH policy and root account hardening:

- disable password and keyboard-interactive SSH auth;
- allow root SSH only with keys by default;
- lock the root password;
- create `/root/.hushlogin`.

Use workload-specific roles for packages, runtime configuration, firewalling, or
application setup.
