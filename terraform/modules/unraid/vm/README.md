<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_libvirt"></a> [libvirt](#requirement\_libvirt) | ~> 0.9.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_libvirt"></a> [libvirt](#provider\_libvirt) | ~> 0.9.6 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [libvirt_domain.this](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/domain) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_vms"></a> [vms](#input\_vms) | Unraid VM definitions and downstream inventory metadata. | <pre>list(object({<br/>    name               = string<br/>    hostname           = optional(string)<br/>    ansible_user       = string<br/>    ip_address         = string<br/>    vm_cores           = number<br/>    vm_memory_mb       = number<br/>    disk_path          = string<br/>    disk_format        = optional(string, "qcow2")<br/>    cloudinit_path     = optional(string)<br/>    mac_address        = string<br/>    smbios_uuid        = optional(string)<br/>    generation_id      = optional(string)<br/>    network_bridge     = optional(string, "br0")<br/>    machine            = optional(string, "pc-q35-10.2")<br/>    os_type            = optional(string, "linux")<br/>    running            = optional(bool, true)<br/>    start_at_node_boot = optional(bool, false)<br/>    shutdown_timeout   = optional(number, 120)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_vms"></a> [vms](#output\_vms) | VM metadata for downstream inventory generation. |
<!-- END_TF_DOCS -->