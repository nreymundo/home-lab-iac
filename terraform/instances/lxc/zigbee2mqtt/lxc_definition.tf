locals {
  zigbee2mqtt = {
    name           = "ct-zigbee2mqtt"
    hostname       = "ct-zigbee2mqtt"
    target_node    = var.zigbee2mqtt_target_node
    vmid           = 404
    ansible_user   = "root"
    cpu_cores      = 2
    memory_mb      = 1024
    swap_mb        = 1024
    rootfs_size_gb = 4
    proxmox_tags = [
      "automation",
      "zigbee2mqtt",
    ]
  }

  lxc_definitions = [
    {
      name         = local.zigbee2mqtt.name
      hostname     = local.zigbee2mqtt.hostname
      target_node  = local.zigbee2mqtt.target_node
      vmid         = local.zigbee2mqtt.vmid
      ansible_user = local.zigbee2mqtt.ansible_user

      # The shared template must exist in the unraid datastore before this
      # root is applied. Template lifecycle is deliberately outside this
      # per-LXC Terraform state.
      template_file_id = var.zigbee2mqtt_template_file_id
      os_type          = "debian"

      unprivileged  = true
      start_on_boot = true
      started       = true
      tags          = local.zigbee2mqtt.proxmox_tags

      ssh_bootstrap = {
        enabled         = true
        package_manager = "apt-get"
        packages        = ["openssh-server"]
        services        = ["ssh"]
        wait_for_ssh    = true
      }

      cpu_cores      = local.zigbee2mqtt.cpu_cores
      memory_mb      = local.zigbee2mqtt.memory_mb
      swap_mb        = local.zigbee2mqtt.swap_mb
      rootfs_size_gb = local.zigbee2mqtt.rootfs_size_gb

      ip_address    = "192.168.20.4"
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
        mknod   = true
      }
    }
  ]
}
