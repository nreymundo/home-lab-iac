locals {
  garage_s3 = {
    name            = "ct-garage-s3"
    hostname        = "ct-garage-s3"
    target_node     = "pve3"
    vmid            = 401
    ip_address      = "192.168.10.71"
    ansible_user    = "root"
    cpu_cores       = 2
    memory_mb       = 4096
    swap_mb         = 1024
    rootfs_size_gb  = 32
    data_host_path  = "/mnt/garage-s3"
    data_guest_path = "/var/lib/garage"
    proxmox_tags = [
      "s3",
      "storage",
    ]
  }

  lxc_definitions = [
    {
      name         = local.garage_s3.name
      hostname     = local.garage_s3.hostname
      target_node  = local.garage_s3.target_node
      vmid         = local.garage_s3.vmid
      ansible_user = local.garage_s3.ansible_user

      template_file_id = "unraid:vztmpl/fedora-44-cloud-amd64.tar.xz"
      os_type          = "fedora"

      unprivileged  = true
      start_on_boot = true
      started       = true
      tags          = local.garage_s3.proxmox_tags

      ssh_bootstrap = {
        enabled = true
      }

      cpu_cores      = local.garage_s3.cpu_cores
      memory_mb      = local.garage_s3.memory_mb
      swap_mb        = local.garage_s3.swap_mb
      rootfs_size_gb = local.garage_s3.rootfs_size_gb

      ip_address = local.garage_s3.ip_address
      dns_servers = [
        "192.168.10.2",
      ]
      network = {
        vlan_id = 10
      }

      features = {
        nesting = true
        keyctl  = true
      }

      mount_points = [
        {
          path      = local.garage_s3.data_guest_path
          volume    = local.garage_s3.data_host_path
          backup    = false
          replicate = false
        }
      ]
    }
  ]
}
