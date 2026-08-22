locals {
  emqx = {
    name           = "ct-emqx"
    hostname       = "ct-emqx"
    target_node    = var.emqx_target_node
    vmid           = 403
    ansible_user   = "root"
    cpu_cores      = 1
    memory_mb      = 512
    swap_mb        = 512
    rootfs_size_gb = 10
    proxmox_tags = [
      "mqtt",
      "automation",
    ]
  }

  lxc_definitions = [
    {
      name         = local.emqx.name
      hostname     = local.emqx.hostname
      target_node  = local.emqx.target_node
      vmid         = local.emqx.vmid
      ansible_user = local.emqx.ansible_user

      # The shared template must exist in the unraid datastore before this
      # root is applied. Template lifecycle is deliberately outside this
      # per-LXC Terraform state.
      template_file_id = var.emqx_template_file_id
      os_type          = "debian"

      unprivileged  = true
      start_on_boot = true
      started       = true
      tags          = local.emqx.proxmox_tags

      ssh_bootstrap = {
        enabled         = true
        package_manager = "apt-get"
        packages        = ["openssh-server"]
        services        = ["ssh"]
        wait_for_ssh    = true
      }

      cpu_cores      = local.emqx.cpu_cores
      memory_mb      = local.emqx.memory_mb
      swap_mb        = local.emqx.swap_mb
      rootfs_size_gb = local.emqx.rootfs_size_gb

      ip_address    = "192.168.20.3"
      ip_prefix_len = 24
      gateway_ip    = "192.168.20.1"
      dns_servers = [
        "192.168.10.1",
      ]
      network = {
        vlan_id = 20
      }

      features = {
        nesting = true
        keyctl  = true
      }
    }
  ]
}
