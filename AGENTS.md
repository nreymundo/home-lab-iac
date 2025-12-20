# AGENTS.md
Use Ansible to provision Raspberry Pi hosts; keep changes minimal and reproducible.
Key paths: ansible/playbooks/rpi.yml; ansible/inventories/rpi/**/*; ansible/roles/common/*.
Commands run from ansible/ unless noted; set `ANSIBLE_CONFIG=ansible/ansible.cfg` if needed.
Install deps: ansible, ansible-lint, yamllint, shfmt, shellcheck, pre-commit.
Always run `ansible-lint` and `ansible-playbook --check` before considering a task done.
Dry-run full: `ansible-playbook -i inventories/rpi/hosts.yml playbooks/rpi.yml --check`.
Apply full: `ansible-playbook -i inventories/rpi/hosts.yml playbooks/rpi.yml`.
Syntax check only: `ansible-playbook -i inventories/rpi/hosts.yml playbooks/rpi.yml --syntax-check`.
Lint: `ansible-lint playbooks/rpi.yml` and `yamllint .` (config in `.yamllint`).
Single-host check: `ansible-playbook -i inventories/rpi/hosts.yml playbooks/rpi.yml --check --limit <host>`.
Packer: `packer fmt -recursive packer/` and `packer validate packer/<template>/` before submitting.
Terraform: `terraform fmt` (run from repo root with `-chdir=terraform`) before submitting when terraform/ changes.
Run `pre-commit run --all-files` before submitting (hooks: ansible-lint, yamllint, packer-fmt, terraform-fmt, etc.).
`common_user` defaults to `ansible_user` else `pi`; set per-host in inventory/host_vars; `ansible_user` can be set in hosts.yml.
Prefer idempotent changes; never commit secrets or host-specific keys; use vault/sops and .gitignore.
YAML/HCL/JSON: spaces only, newline at EOF, keep lines ≲120 chars.
Keep comments minimal and purposeful; document new components with nearby README snippets.
Ansible: keep defaults in roles, host/group vars per env; avoid redefining defaults unnecessarily.
Maintain role structure (tasks/handlers/defaults/templates); favor handlers for restarts.
Scripts: POSIX-sh, explicit deps at top, `set -euo pipefail` when sensible.
Naming: descriptive, lowercase with hyphens/underscores; inventory hostnames match actual hostnames.
Error handling: fail fast; avoid blindly ignoring tasks; surface why changes are made.
No Cursor/Copilot rules present as of this file.
If unsure about infra impact, propose the plan before applying.
