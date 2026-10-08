# Cockpit

Optional per-host Ubuntu console, disabled by default. The unified Ubuntu
playbook always enters this role so disabling can clean up previously managed
state without touching a never-managed installation.

| Variable | Default | Purpose |
| --- | --- | --- |
| `cockpit_enabled` | `false` | Manage the console's selected packages and socket |
| `cockpit_packages` | `[cockpit-ws, cockpit-bridge, cockpit-system]` | Base console without implicit NetworkManager recommendations |
| `cockpit_extensions` | `[]` | Explicit extension packages, e.g. `cockpit-storaged` |
| `cockpit_ufw_sources` | `[]` | Source CIDRs allowed to TCP 9090; requires managed/enabled UFW |

State in `/etc/cockpit/ansible-state.json` records selected packages and firewall
sources. Deselecting extensions or sources removes the previously recorded
selection. Disabling stops the socket and service, removes managed packages and
rules, then removes the state file. No automatic apt autoremove is used.

The web console at `https://HOST:9090` authenticates local accounts using their
passwords. SSH key access and NOPASSWD sudo are independent and do not set a local
password. This role never creates or resets passwords. Cockpit Client can use SSH
and `cockpit-bridge` for key-based access. Use separate host consoles; do not
configure the deprecated web multi-host switcher.
