# Hetzner Terraform Modules

The Hetzner modules separate server provisioning from project-wide SSH keys
and firewalls so each can have its own Terraform state and lifecycle.

## Module Reference

- [`firewall`](firewall/README.md) manages firewalls and returns IDs and rule metadata keyed by logical name.
- [`ssh_keys`](ssh_keys/README.md) manages project SSH keys and returns both keyed IDs and a flat list of IDs.
- [`vm`](vm/README.md) manages servers, optional attachments to existing private networks, and optional data volumes. It accepts existing `firewall_ids` and `ssh_key_ids`; it does not create those project resources.

## Repository Deployments

- The [firewall root](../../cloud/hetzner/firewall/) publishes firewall IDs and rule metadata. The [NetBird root](../../cloud/hetzner/servers/netbird/) reads those outputs from S3 remote state to select bootstrap firewalls and derive guest UFW rules.
- The [SSH-key root](../../cloud/hetzner/ssh_keys/) publishes project key IDs. NetBird does not consume that state: it reads 1Password public keys directly and supplies them to guest cloud-init.

## Cloud-Init and Server Lifecycle

- Explicit `user_data` takes precedence over generated cloud-init. If neither per-VM nor module-wide cloud-init is configured, the module does not generate user data.
- Per-VM `username`, `ssh_authorized_keys`, and `ssh_port` override corresponding module defaults. The SSH port defaults to `22`. Extra packages are combined and deduplicated; UFW rules are appended in default-then-VM order.
- Generated cloud-init requires a non-empty username and at least one authorized key.

- The VM module attaches `firewall_ids` during server creation. Terraform ignores subsequent changes to `ssh_keys`, `user_data`, and `firewall_ids` on existing servers; changing those inputs does not update an existing server.
