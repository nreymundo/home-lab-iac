<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |
| <a name="requirement_bitwarden-secrets"></a> [bitwarden-secrets](#requirement\_bitwarden-secrets) | 0.5.4-pre |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.106 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_bitwarden-secrets"></a> [bitwarden-secrets](#provider\_bitwarden-secrets) | 0.5.4-pre |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | ~> 0.106 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_download_file.lxc_image](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/download_file) | resource |
| [proxmox_virtual_environment_container.this](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_container) | resource |
| [bitwarden-secrets_secret.ssh_public_keys](https://registry.terraform.io/providers/bitwarden/bitwarden-secrets/0.5.4-pre/docs/data-sources/secret) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_containers"></a> [containers](#input\_containers) | LXC container definitions to provision in Proxmox. | <pre>list(object({<br/>    name        = string<br/>    target_node = string<br/>    vmid        = number<br/><br/>    ansible_user = optional(string, "root")<br/>    description  = optional(string, "Managed by Terraform")<br/>    hostname     = optional(string)<br/><br/>    template_file_id = optional(string)<br/>    image = optional(object({<br/>      url                 = string<br/>      datastore_id        = optional(string, "local")<br/>      file_name           = optional(string)<br/>      checksum            = optional(string)<br/>      checksum_algorithm  = optional(string)<br/>      upload_timeout      = optional(number)<br/>      overwrite           = optional(bool)<br/>      overwrite_unmanaged = optional(bool)<br/>      verify              = optional(bool)<br/>    }))<br/>    os_type = optional(string, "unmanaged")<br/><br/>    unprivileged  = optional(bool, true)<br/>    start_on_boot = optional(bool, true)<br/>    started       = optional(bool, true)<br/>    protection    = optional(bool, false)<br/>    tags          = optional(list(string), [])<br/><br/>    cpu_cores        = number<br/>    cpu_architecture = optional(string, "amd64")<br/>    cpu_limit        = optional(number, 0)<br/>    cpu_units        = optional(number, 1024)<br/><br/>    memory_mb = number<br/>    swap_mb   = optional(number, 0)<br/><br/>    rootfs_datastore_id = optional(string, "ssd-zfs")<br/>    rootfs_size_gb      = number<br/>    rootfs_mount_options = optional(list(string), [<br/>      "noatime",<br/>    ])<br/><br/>    ip_address    = optional(string)<br/>    ip_prefix_len = optional(number, 24)<br/>    gateway_ip    = optional(string, "192.168.10.1")<br/>    dns_servers   = optional(list(string), ["192.168.10.1"])<br/>    dns_domain    = optional(string)<br/><br/>    network = optional(object({<br/>      name         = optional(string, "eth0")<br/>      bridge       = optional(string, "vmbr0")<br/>      enabled      = optional(bool, true)<br/>      firewall     = optional(bool, false)<br/>      host_managed = optional(bool, false)<br/>      vlan_id      = optional(number)<br/>      mac_address  = optional(string)<br/>      mtu          = optional(number)<br/>      rate_limit   = optional(number)<br/>    }), {})<br/><br/>    features = optional(object({<br/>      nesting = optional(bool, false)<br/>      fuse    = optional(bool, false)<br/>      keyctl  = optional(bool, false)<br/>      mknod   = optional(bool, false)<br/>      mount   = optional(list(string), [])<br/>    }), {})<br/><br/>    mount_points = optional(list(object({<br/>      path          = string<br/>      volume        = string<br/>      size          = optional(string)<br/>      read_only     = optional(bool)<br/>      backup        = optional(bool)<br/>      replicate     = optional(bool)<br/>      shared        = optional(bool)<br/>      acl           = optional(bool)<br/>      quota         = optional(bool)<br/>      mount_options = optional(list(string))<br/>    })), [])<br/><br/>    device_passthrough = optional(list(object({<br/>      path       = string<br/>      deny_write = optional(bool)<br/>      uid        = optional(number)<br/>      gid        = optional(number)<br/>      mode       = optional(string)<br/>    })), [])<br/><br/>    idmaps = optional(list(object({<br/>      type         = string<br/>      container_id = number<br/>      host_id      = number<br/>      size         = number<br/>    })), [])<br/><br/>    environment_variables = optional(map(string), {})<br/>    ssh_public_keys       = optional(list(string), [])<br/><br/>    ssh_bootstrap = optional(object({<br/>      enabled          = optional(bool, false)<br/>      package_manager  = optional(string, "dnf")<br/>      packages         = optional(list(string), ["openssh-server"])<br/>      services         = optional(list(string), ["sshd"])<br/>      wait_for_ssh     = optional(bool, true)<br/>      ssh_user         = optional(string, "root")<br/>      connect_timeout  = optional(number, 5)<br/>      timeout_attempts = optional(number, 30)<br/>      retry_delay      = optional(number, 2)<br/>    }), {})<br/><br/>    startup = optional(object({<br/>      order      = string<br/>      up_delay   = optional(string)<br/>      down_delay = optional(string)<br/>    }))<br/><br/>    wait_for_ip = optional(object({<br/>      ipv4 = optional(bool, false)<br/>      ipv6 = optional(bool, false)<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_ssh_bootstrap_cluster_ssh_host"></a> [ssh\_bootstrap\_cluster\_ssh\_host](#input\_ssh\_bootstrap\_cluster\_ssh\_host) | SSH target for any Proxmox cluster node used to resolve target\_node IPs and bootstrap SSH inside LXCs. Required when any container enables ssh\_bootstrap. | `string` | `null` | no |
| <a name="input_ssh_bootstrap_node_ssh_user"></a> [ssh\_bootstrap\_node\_ssh\_user](#input\_ssh\_bootstrap\_node\_ssh\_user) | SSH user used when connecting to the resolved target\_node IP for pct exec. | `string` | `"root"` | no |
| <a name="input_ssh_public_keys"></a> [ssh\_public\_keys](#input\_ssh\_public\_keys) | Additional SSH public keys to add to all containers. | `list(string)` | `[]` | no |
| <a name="input_ssh_public_keys_secret_id"></a> [ssh\_public\_keys\_secret\_id](#input\_ssh\_public\_keys\_secret\_id) | Bitwarden Secrets Manager secret ID containing newline-delimited SSH public keys. Set to null to disable. | `string` | `"9b5f1231-f792-4e85-96f1-b3c60002f839"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_containers"></a> [containers](#output\_containers) | Normalized LXC metadata for downstream inventory generation. |
| <a name="output_template_file_ids"></a> [template\_file\_ids](#output\_template\_file\_ids) | Template file IDs used by each LXC container. |
<!-- END_TF_DOCS -->
