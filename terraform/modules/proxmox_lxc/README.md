# Proxmox LXC Module

Reusable module for creating Proxmox LXC containers with the `bpg/proxmox`
provider.

The module supports either pre-existing LXC templates via `template_file_id` or
Terraform-managed template downloads via `image.url`. Use `image.url` when the
template should be part of the Terraform source of truth.

Example:

```hcl
module "proxmox_lxc" {
  source = "../../../modules/proxmox_lxc"

  containers = [
    {
      name        = "llm"
      target_node = "pve3"
      vmid        = 300

      image = {
        url       = "https://images.linuxcontainers.org/images/fedora/43/amd64/default/20260425_20:33/rootfs.tar.xz"
        file_name = "fedora-43-default-20260425-amd64-rootfs.tar.xz"
      }
      os_type = "fedora"

      cpu_cores       = 8
      memory_mb       = 32768
      rootfs_size_gb  = 64
      ip_address      = "192.168.10.20"
      start_on_boot   = true
      rootfs_datastore_id = "ssd-zfs"

      mount_points = [
        {
          path   = "/models"
          volume = "/mnt/models"
        }
      ]

      device_passthrough = [
        {
          path = "/dev/dri/renderD128"
          mode = "0660"
        }
      ]
    }
  ]
}
```
