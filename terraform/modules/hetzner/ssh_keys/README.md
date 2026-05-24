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
| [hcloud_ssh_key.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/ssh_key) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_default_labels"></a> [default\_labels](#input\_default\_labels) | Module-level labels merged into each SSH key label map | `map(string)` | `{}` | no |
| <a name="input_ssh_keys"></a> [ssh\_keys](#input\_ssh\_keys) | Hetzner SSH keys to create, keyed by a stable identifier | <pre>map(object({<br/>    name       = optional(string)<br/>    public_key = string<br/>    labels     = optional(map(string), {})<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ssh_key_id_list"></a> [ssh\_key\_id\_list](#output\_ssh\_key\_id\_list) | Flat list of Hetzner SSH key IDs for direct VM-module composition |
| <a name="output_ssh_key_ids"></a> [ssh\_key\_ids](#output\_ssh\_key\_ids) | SSH key IDs keyed by stable SSH key identifier |
| <a name="output_ssh_keys"></a> [ssh\_keys](#output\_ssh\_keys) | SSH key metadata keyed by stable SSH key identifier |
<!-- END_TF_DOCS -->
