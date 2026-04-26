# Hetzner Terraform Modules

This directory contains a small Hetzner module family split by responsibility instead of putting all resources into one large module.

## Modules

- `vm/`
  - Creates Hetzner servers, optional private network attachments, optional data volumes, and volume attachments.
  - Consumes `ssh_key_ids` and `firewall_ids` as inputs.
- `firewall/`
  - Creates Hetzner firewalls and exposes their IDs for downstream consumers.
- `ssh_keys/`
  - Creates Hetzner SSH keys and exposes their IDs for downstream consumers.

## Why split it this way?

- SSH keys are often account- or project-scoped and reused across multiple servers.
- Firewalls can be shared across multiple servers or server groups.
- VM lifecycle is usually different from SSH key and firewall lifecycle.

Keeping them separate lets Terraform manage all three resource types while preserving clean lifecycle boundaries.

## Composition model

Typical usage is:

1. Create SSH keys with `hetzner/ssh_keys`
2. Create one or more firewalls with `hetzner/firewall`
3. Pass the resulting IDs into `hetzner/vm`

## Example

```hcl
module "ssh_keys" {
  source = "../../modules/hetzner/ssh_keys"

  default_labels = {
    managed_by = "terraform"
    environment = "production"
  }

  ssh_keys = {
    admin = {
      name       = "admin"
      public_key = file("~/.ssh/id_ed25519.pub")
    }
  }
}

module "firewall" {
  source = "../../modules/hetzner/firewall"

  default_labels = {
    managed_by = "terraform"
    environment = "production"
  }

  firewalls = {
    ssh = {
      name = "ssh-only"
      rules = [
        {
          direction   = "in"
          protocol    = "tcp"
          port        = "22"
          source_ips  = ["0.0.0.0/0", "::/0"]
          description = "Allow SSH"
        },
        {
          direction       = "out"
          protocol        = "tcp"
          port            = "any"
          destination_ips = ["0.0.0.0/0", "::/0"]
          description     = "Allow outbound TCP"
        }
      ]
    }
  }
}

module "vm" {
  source = "../../modules/hetzner/vm"

  default_labels = {
    managed_by = "terraform"
    environment = "production"
  }

  default_cloud_init = {
    username            = "ubuntu"
    ssh_authorized_keys = [file("~/.ssh/id_ed25519.pub")]
    ssh_port            = 22
    extra_packages      = ["jq"]
  }

  vms = [
    {
      name        = "public-vps-01"
      server_type = "cx22"
      image       = "ubuntu-24.04"
      location    = "nbg1"

      ssh_key_ids  = module.ssh_keys.ssh_key_id_list
      firewall_ids = [module.firewall.firewall_ids.ssh]

      labels = {
        role = "edge"
      }

      cloud_init = {
        ufw_rules = [
          {
            port     = "443"
            protocol = "tcp"
          }
        ]
      }

      private_network = {
        network_id = 123456
        ip         = "10.42.0.10"
      }

      volumes = [
        {
          name      = "data"
          size      = 20
          format    = "ext4"
          automount = true
        }
      ]
    }
  ]
}
```

## Input / output summary

### `ssh_keys`

Inputs:
- `ssh_keys` — map of key definitions
- `default_labels`

Outputs:
- `ssh_key_ids`
- `ssh_key_id_list`
- `ssh_keys`

### `firewall`

Inputs:
- `firewalls` — map of firewall definitions and rules
- `default_labels`

Outputs:
- `firewall_ids`
- `firewalls`

### `vm`

Inputs:
- `vms` — list of VM definitions
- `default_labels`
- `default_cloud_init` — optional module-wide baseline for generated cloud-init

Outputs:
- `vms` — map keyed by VM name, including server metadata and attached volume metadata

Cloud-init merge behavior:
- If `user_data` is set on a VM, the module uses it directly and does not generate cloud-init for that VM.
- `username`, `ssh_authorized_keys`, and `ssh_port` use the per-VM `cloud_init` value when present; otherwise they fall back to `default_cloud_init`.
- `extra_packages` combines the default and per-VM lists, then de-duplicates them.
- `ufw_rules` combines the default and per-VM lists in order.

## Notes

- The `vm` module intentionally uses `firewall_ids` directly on `hcloud_server`, so firewalls are attached before first boot.
- The `vm` module intentionally treats `ssh_keys` as create-time input and ignores later changes to avoid forcing server replacement.
- The `vm` module does not create SSH keys or firewalls itself; those are managed in the sibling modules above and composed at the caller/root level.
