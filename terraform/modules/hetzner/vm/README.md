<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_hcloud"></a> [hcloud](#requirement\_hcloud) | ~> 1.61 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_hcloud"></a> [hcloud](#provider\_hcloud) | ~> 1.61 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [hcloud_server.vms](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/server) | resource |
| [hcloud_server_network.private](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/server_network) | resource |
| [hcloud_volume.data](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/volume) | resource |
| [hcloud_volume_attachment.data](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/volume_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_cloud_init"></a> [default\_cloud\_init](#input\_default\_cloud\_init) | Default generated cloud-init settings applied to VMs unless overridden per VM | <pre>object({<br/>    username            = string<br/>    ssh_authorized_keys = list(string)<br/>    ssh_port            = optional(number, 22)<br/>    extra_packages      = optional(list(string), [])<br/>    ufw_rules = optional(list(object({<br/>      port     = string<br/>      protocol = optional(string, "tcp")<br/>    })), [])<br/>  })</pre> | `null` | no |
| <a name="input_default_labels"></a> [default\_labels](#input\_default\_labels) | Module-level labels merged into each VM label map | `map(string)` | `{}` | no |
| <a name="input_vms"></a> [vms](#input\_vms) | Normalized VM definitions to provision in Hetzner Cloud | <pre>list(object({<br/>    name        = string<br/>    server_type = string<br/>    image       = string<br/>    location    = string<br/>    ssh_key_ids = optional(list(number), [])<br/>    cloud_init = optional(object({<br/>      username            = optional(string)<br/>      ssh_authorized_keys = optional(list(string))<br/>      ssh_port            = optional(number)<br/>      extra_packages      = optional(list(string), [])<br/>      ufw_rules = optional(list(object({<br/>        port     = string<br/>        protocol = optional(string, "tcp")<br/>      })), [])<br/>    }), null)<br/>    firewall_ids       = optional(list(number), [])<br/>    placement_group_id = optional(number, null)<br/>    labels             = optional(map(string), {})<br/>    backups            = optional(bool, false)<br/>    user_data          = optional(string, null)<br/>    delete_protection  = optional(bool, false)<br/>    rebuild_protection = optional(bool, false)<br/>    enable_public_ipv4 = optional(bool, true)<br/>    enable_public_ipv6 = optional(bool, true)<br/>    private_network = optional(object({<br/>      network_id = number<br/>      ip         = optional(string, null)<br/>      alias_ips  = optional(list(string), [])<br/>    }), null)<br/>    volumes = optional(list(object({<br/>      name      = string<br/>      size      = number<br/>      format    = optional(string, null)<br/>      automount = optional(bool, false)<br/>      labels    = optional(map(string), {})<br/>    })), [])<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_vms"></a> [vms](#output\_vms) | VM metadata keyed by VM name for downstream consumers |
<!-- END_TF_DOCS -->
