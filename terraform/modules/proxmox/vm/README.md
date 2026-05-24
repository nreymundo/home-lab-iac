<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_bitwarden-secrets"></a> [bitwarden-secrets](#requirement\_bitwarden-secrets) | 0.5.4-pre |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 3.0.2-rc07 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_bitwarden-secrets"></a> [bitwarden-secrets](#provider\_bitwarden-secrets) | 0.5.4-pre |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 3.0.2-rc07 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_vm_qemu.this](https://registry.terraform.io/providers/telmate/proxmox/3.0.2-rc07/docs/resources/vm_qemu) | resource |
| [bitwarden-secrets_secret.ssh_public_keys](https://registry.terraform.io/providers/bitwarden/bitwarden-secrets/0.5.4-pre/docs/data-sources/secret) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ssh_public_keys"></a> [ssh\_public\_keys](#input\_ssh\_public\_keys) | Additional SSH public keys to add to all VMs. | `list(string)` | `[]` | no |
| <a name="input_ssh_public_keys_secret_id"></a> [ssh\_public\_keys\_secret\_id](#input\_ssh\_public\_keys\_secret\_id) | Bitwarden Secrets Manager secret ID containing newline-delimited SSH public keys. Set to null to disable. | `string` | `"9b5f1231-f792-4e85-96f1-b3c60002f839"` | no |
| <a name="input_vms"></a> [vms](#input\_vms) | Normalized VM definitions to provision in Proxmox | <pre>list(object({<br/>    name                        = string<br/>    target_node                 = string<br/>    vmid                        = number<br/>    template_name               = optional(string, "ubuntu-24.04-base")<br/>    ci_user                     = string<br/>    ansible_user                = string<br/>    ip_address                  = string<br/>    ip_prefix_len               = optional(number, 24)<br/>    gateway_ip                  = optional(string, "192.168.10.1")<br/>    dns_server                  = optional(string, "192.168.10.1")<br/>    network_bridge              = optional(string, "vmbr0")<br/>    vlan_id                     = optional(number, 10)<br/>    vm_cores                    = number<br/>    vm_memory_mb                = number<br/>    vm_balloon_mb               = number<br/>    ballooning_enabled          = optional(bool)<br/>    vm_disk_size_gb             = number<br/>    storage_pool                = optional(string, "ssd-zfs")<br/>    secondary_disk_enabled      = optional(bool, false)<br/>    secondary_disk_storage_pool = optional(string)<br/>    secondary_disk_size_gb      = optional(number, 0)<br/>    proxmox_tags                = optional(list(string), [])<br/>    machine                     = optional(string, "q35")<br/>    pci_devices = optional(list(object({<br/>      id     = string<br/>      pcie   = optional(bool, true)<br/>      rombar = optional(bool, true)<br/>    })), [])<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_vms"></a> [vms](#output\_vms) | Normalized VM metadata for downstream inventory generation |
<!-- END_TF_DOCS -->
