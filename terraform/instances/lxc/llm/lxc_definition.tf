locals {
  llm = {
    name             = "ct-llm"
    hostname         = "ct-llm"
    target_node      = "pve3"
    vmid             = 400
    ip_address       = "192.168.10.70"
    ansible_user     = "root"
    cpu_cores        = 12
    memory_mb        = 98304
    swap_mb          = 8192
    rootfs_size_gb   = 128
    model_host_path  = "/mnt/ai-files"
    model_guest_path = "/opt/ai"
    proxmox_tags = [
      "ai",
      "amd",
      "gpu",
      "llm",
    ]
  }

  lxc_definitions = [
    {
      name         = local.llm.name
      hostname     = local.llm.hostname
      target_node  = local.llm.target_node
      vmid         = local.llm.vmid
      ansible_user = local.llm.ansible_user

      template_file_id = "unraid:vztmpl/fedora-44-cloud-amd64.tar.xz"
      os_type          = "fedora"

      unprivileged  = true
      start_on_boot = true
      started       = true
      tags          = local.llm.proxmox_tags

      ssh_bootstrap = {
        enabled = true
      }

      cpu_cores      = local.llm.cpu_cores
      memory_mb      = local.llm.memory_mb
      swap_mb        = local.llm.swap_mb
      rootfs_size_gb = local.llm.rootfs_size_gb

      ip_address = local.llm.ip_address
      dns_servers = [
        "192.168.10.2",
      ]
      network = {
        vlan_id = 10
      }

      features = {
        nesting = true
        fuse    = false
        keyctl  = true
        mknod   = true
      }

      mount_points = [
        {
          path      = local.llm.model_guest_path
          volume    = local.llm.model_host_path
          backup    = false
          replicate = false
        }
      ]

      device_passthrough = [
        {
          path = "/dev/kfd"
          mode = "0660"
        },
        {
          path = "/dev/dri/renderD128"
          mode = "0660"
        },
        {
          path = "/dev/dri/card1"
          mode = "0660"
        }
      ]
    }
  ]
}
