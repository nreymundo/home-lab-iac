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
| [hcloud_firewall.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/firewall) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_labels"></a> [default\_labels](#input\_default\_labels) | Module-level labels merged into each firewall label map | `map(string)` | `{}` | no |
| <a name="input_firewalls"></a> [firewalls](#input\_firewalls) | Hetzner firewalls to create, keyed by a stable identifier | <pre>map(object({<br/>    name   = optional(string)<br/>    labels = optional(map(string), {})<br/>    rules = list(object({<br/>      direction       = string<br/>      protocol        = string<br/>      port            = optional(string)<br/>      source_ips      = optional(list(string))<br/>      destination_ips = optional(list(string))<br/>      description     = optional(string)<br/>    }))<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_firewall_ids"></a> [firewall\_ids](#output\_firewall\_ids) | Firewall IDs keyed by stable firewall identifier |
| <a name="output_firewalls"></a> [firewalls](#output\_firewalls) | Firewall metadata keyed by stable firewall identifier |
<!-- END_TF_DOCS -->
