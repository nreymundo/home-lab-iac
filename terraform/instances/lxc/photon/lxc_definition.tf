locals {
  photon = {
    name            = "ct-photon"
    hostname        = "ct-photon"
    target_node     = "pve3"
    vmid            = 402
    ip_address      = "192.168.10.72"
    ansible_user    = "root"
    cpu_cores       = 4
    memory_mb       = 16384
    swap_mb         = 4096
    rootfs_size_gb  = 32
    data_size       = "500G"
    data_guest_path = "/opt/photon"
    proxmox_tags = [
      "geocoding",
      "photon",
    ]
  }

  lxc_definitions = [
    {
      name         = local.photon.name
      hostname     = local.photon.hostname
      target_node  = local.photon.target_node
      vmid         = local.photon.vmid
      ansible_user = local.photon.ansible_user

      template_file_id = "unraid:vztmpl/fedora-44-cloud-amd64.tar.xz"
      os_type          = "fedora"

      unprivileged  = true
      start_on_boot = true
      started       = true
      tags          = local.photon.proxmox_tags

      ssh_bootstrap = {
        enabled = true
      }

      cpu_cores      = local.photon.cpu_cores
      memory_mb      = local.photon.memory_mb
      swap_mb        = local.photon.swap_mb
      rootfs_size_gb = local.photon.rootfs_size_gb

      ip_address = local.photon.ip_address
      dns_servers = [
        "192.168.10.2",
      ]
      network = {
        vlan_id = 10
      }

      features = {
        nesting = true
        keyctl  = true
        mknod   = true
      }

      mount_points = [
        {
          path      = local.photon.data_guest_path
          volume    = "ssd-zfs"
          size      = local.photon.data_size
          backup    = false
          replicate = false
        }
      ]
    }
  ]
}
