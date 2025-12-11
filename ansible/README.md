### Ansible – Raspberry Pi Provisioning

Initial scaffolding to manage Raspberry Pi hosts (3/4/5/CM) with common hardening and per-host packages.

Structure:
- `playbooks/rpi.yml` targets the `rpi` inventory group and applies the `common` role.
- `inventories/rpi/hosts.yml` holds Pi hosts in YAML format; set `ansible_user` per host for SSH login.
- `inventories/rpi/group_vars/rpi.yml` sets shared defaults (user, SSH hardening, common packages, authorized keys, timezone, NTP).
- `inventories/rpi/host_vars/<hostname>.yml` allows host-specific settings such as `common_extra_packages`, `common_netplan_config`, or `common_ntp_servers`.
- `roles/common` contains the tasks/handlers/defaults for updates, SSH hardening, keys, packages, unattended upgrades, and `.hushlogin`.

Usage:
1. Update `inventories/rpi/hosts.yml` with real hosts/IPs and set `ansible_user` per host (e.g., `nico`).
2. Replace the sample keys in `inventories/rpi/group_vars/rpi.yml` with your public keys.
3. Add host vars (e.g., `inventories/rpi/host_vars/main-rpi4.yml`) for unique packages or per-host settings (extra packages, netplan config).
4. Run commands from the `ansible/` directory (or set `ANSIBLE_CONFIG=ansible/ansible.cfg` if running from repo root):
   - `ansible-playbook -i inventories/rpi/hosts.yml playbooks/rpi.yml --check` (dry run)
   - `ansible-playbook -i inventories/rpi/hosts.yml playbooks/rpi.yml`
5. Before committing changes, run `pre-commit run --all-files` (or `ansible-lint playbooks/rpi.yml` + `yamllint .`).

Notes:
- `common_user` defaults to `ansible_user` (from `hosts.yml`) else `pi`; used for authorized_keys, `.hushlogin`, and home paths.
- `common_extra_packages` is merged per host; `common_packages` apply to all.
- `common_timezone` sets the system timezone via `timedatectl`.
- `common_ntp_servers` installs/enables systemd-timesyncd and configures `/etc/systemd/timesyncd.conf.d/20-ansible.conf`.
- `common_netplan_config` (optional) renders `/etc/netplan/01-main.yaml` when provided and triggers `netplan apply`.
- Hostname is set to match the inventory name (`inventory_hostname`) during provisioning.
- SSH hardening edits `/etc/ssh/sshd_config` and restarts `ssh`. Ensure you have key access first.
- A `.hushlogin` file is created in the common user's home to suppress login banners.
