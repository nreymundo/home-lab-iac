<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_libvirt"></a> [libvirt](#requirement\_libvirt) | ~> 0.9.6 |
| <a name="requirement_macaddress"></a> [macaddress](#requirement\_macaddress) | ~> 0.3.2 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.9 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_libvirt"></a> [libvirt](#provider\_libvirt) | ~> 0.9.6 |
| <a name="provider_macaddress"></a> [macaddress](#provider\_macaddress) | ~> 0.3.2 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.9 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [libvirt_domain.this](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/domain) | resource |
| [macaddress_macaddress.nic](https://registry.terraform.io/providers/ivoronin/macaddress/latest/docs/resources/macaddress) | resource |
| [random_uuid.generation](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_vms"></a> [vms](#input\_vms) | Unraid VM definitions and downstream inventory metadata. | <pre>list(object({<br/>    name               = string<br/>    hostname           = optional(string)<br/>    ansible_user       = string<br/>    ip_address         = string<br/>    vm_cores           = number<br/>    vm_memory_mb       = number<br/>    disk_path          = string<br/>    disk_format        = optional(string, "qcow2")<br/>    cloudinit_path     = optional(string)<br/>    network_bridge     = optional(string, "br0")<br/>    machine            = optional(string, "pc-q35-10.2")<br/>    os_type            = optional(string, "linux")<br/>    running            = optional(bool, true)<br/>    start_at_node_boot = optional(bool, false)<br/>    shutdown_timeout   = optional(number, 120)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_vms"></a> [vms](#output\_vms) | VM metadata for downstream inventory generation. |
<!-- END_TF_DOCS -->