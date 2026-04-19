locals {
  k3s = {
    default_ci_user        = "ubuntu"
    ip_prefix_len          = 24
    node_ip_start          = "192.168.10.50"
    node_vmid_start        = 200
    vm_cores               = 8
    vm_memory_mb           = 24576
    vm_balloon_mb          = 16384
    vm_disk_size_gb        = 128
    secondary_disk_enabled = true
    secondary_disk_size_gb = 600
    proxmox_nodes          = ["pve1", "pve2"]
    nodes = [
      {
        ci_user     = "ubuntu"
        target_node = "pve1"
        pci_devices = [
          {
            # Requires manual creation of 'intel-igpu' PCI Resource Mapping in Proxmox Datacenter
            id = "intel-igpu"
          }
        ]
      },
      {
        ci_user     = "ubuntu"
        target_node = "pve2"
        pci_devices = [
          {
            # Requires manual creation of 'intel-igpu' PCI Resource Mapping in Proxmox Datacenter
            id = "intel-igpu"
          }
        ]
      }
    ]
  }

  node_ip_subnet      = "${join(".", slice(split(".", local.k3s.node_ip_start), 0, 3))}.0/${local.k3s.ip_prefix_len}"
  node_ip_start_octet = tonumber(split(".", local.k3s.node_ip_start)[3])
  node_count          = length(local.k3s.nodes)
  node_ci_users = [
    for node in local.k3s.nodes : coalesce(try(node.ci_user, null), local.k3s.default_ci_user)
  ]
  node_ansible_users = [
    for node_index, node in local.k3s.nodes : coalesce(try(node.ansible_user, null), local.node_ci_users[node_index])
  ]
  node_resource_defaults = {
    vm_cores               = local.k3s.vm_cores
    vm_memory_mb           = local.k3s.vm_memory_mb
    vm_balloon_mb          = local.k3s.vm_balloon_mb
    vm_disk_size_gb        = local.k3s.vm_disk_size_gb
    secondary_disk_size_gb = local.k3s.secondary_disk_size_gb
  }
  _node_resource_overrides = {
    for attr, default_value in local.node_resource_defaults :
    attr => [for node in local.k3s.nodes : coalesce(try(node[attr], null), default_value)]
  }
  node_cores                  = local._node_resource_overrides.vm_cores
  node_memory_mb              = local._node_resource_overrides.vm_memory_mb
  node_balloon_mb             = local._node_resource_overrides.vm_balloon_mb
  node_disk_size_gb           = local._node_resource_overrides.vm_disk_size_gb
  node_secondary_disk_size_gb = local._node_resource_overrides.secondary_disk_size_gb
  node_target_nodes = [
    for node_index, node in local.k3s.nodes : coalesce(try(node.target_node, null), element(local.k3s.proxmox_nodes, node_index % length(local.k3s.proxmox_nodes)))
  ]
  vm_definitions = [
    for node_index, node in local.k3s.nodes : merge(
      {
        name                   = "k3s-node-${format("%02d", node_index + 1)}"
        target_node            = local.node_target_nodes[node_index]
        vmid                   = local.k3s.node_vmid_start + node_index
        ci_user                = local.node_ci_users[node_index]
        ansible_user           = local.node_ansible_users[node_index]
        ip_address             = cidrhost(local.node_ip_subnet, local.node_ip_start_octet + node_index)
        ip_prefix_len          = local.k3s.ip_prefix_len
        vm_cores               = local.node_cores[node_index]
        vm_memory_mb           = local.node_memory_mb[node_index]
        vm_balloon_mb          = local.node_balloon_mb[node_index]
        vm_disk_size_gb        = local.node_disk_size_gb[node_index]
        secondary_disk_enabled = local.k3s.secondary_disk_enabled
        secondary_disk_size_gb = local.node_secondary_disk_size_gb[node_index]
        proxmox_tags           = ["k3s-node"]
        pci_devices            = try(node.pci_devices, [])
      },
      try(node.template_name, null) == null ? {} : { template_name = node.template_name },
      try(node.machine, null) == null ? {} : { machine = node.machine }
    )
  ]
}
