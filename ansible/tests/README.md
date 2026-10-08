# Offline host provisioning tests

From the repository root:

```sh
python -m unittest discover -s ansible/tests -v
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint --project-dir ansible ansible/playbooks/ ansible/roles/
```

Use Python with Ansible, Jinja2 and PyYAML installed, plus the repository's
Ansible collections. The pinned CI versions are in
[`../../.github/workflows/ci.yml`](../../.github/workflows/ci.yml). The suite
uses standard-library `unittest`; no pytest dependency is required.

The SSH tests require `sshd` and `ssh-keygen` in `PATH`. They generate a temporary
host key and inspect temporary configurations with `sshd -T`; they never open
an SSH listener or connect to a host. Missing OpenSSH tools skip these tests
locally; CI installs and checks the tools so that coverage runs there.

Repository tests require Ubuntu's `python3-apt` and system Python.
They run the role's helper against the real APT source library with an isolated
`APT_CONFIG` and temporary source files, exercising deb822 and legacy sources, missing
components, third-party preservation and idempotence. They skip on controllers
without that Ubuntu library; CI installs it and runs them.

Fixtures use temporary directories for rendered configuration, file lifecycle
checks, and simulated hardware interfaces. Local Ansible fixtures execute
assertions or redirect file operations into those directories. They do not run
the provisioning playbook against the controller, edit its `/etc` or `/sys`,
contact inventory hosts, or retrieve 1Password secrets.

These tests establish configuration and helper behavior. First provisioning,
fresh SSH/sudo access, real GPU acceleration and power enforcement, service
behavior, and reboot persistence still require target machines.

Power fixtures reproduce Linux's flat `constraint_N_*` ABI and cover PPD/RAPL,
class symlinks, bounded traversal, preferences and drift. Composition checks use
Ansible inventory and condition evaluation without connecting to target hosts.
Ansible execution fixtures need permission to create a local Unix socket for the
controller RPC manager; restricted environments can run helper/composition tests
but must use CI for the complete suite. Do not turn those failures into skips.
