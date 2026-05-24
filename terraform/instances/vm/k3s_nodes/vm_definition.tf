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
    proxmox_nodes          = ["pve1", "pve2", "pve3"]
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
      },
      {
        ci_user     = "ubuntu"
        target_node = "pve3"
        labels = {
          "homelab.lan/cpu-vendor" = "amd"
        }
      }
    ]
  }

  node_ip_subnet      = "${join(".", slice(split(".", local.k3s.node_ip_start), 0, 3))}.0/${local.k3s.ip_prefix_len}"
  node_ip_start_octet = tonumber(split(".", local.k3s.node_ip_start)[3])

  normalized_nodes = [
    for node_index, node in local.k3s.nodes : merge(node, {
      ci_user                = coalesce(try(node.ci_user, null), local.k3s.default_ci_user)
      ansible_user           = coalesce(try(node.ansible_user, null), coalesce(try(node.ci_user, null), local.k3s.default_ci_user))
      target_node            = coalesce(try(node.target_node, null), element(local.k3s.proxmox_nodes, node_index % length(local.k3s.proxmox_nodes)))
      vm_cores               = coalesce(try(node.vm_cores, null), local.k3s.vm_cores)
      vm_memory_mb           = coalesce(try(node.vm_memory_mb, null), local.k3s.vm_memory_mb)
      vm_balloon_mb          = coalesce(try(node.vm_balloon_mb, null), local.k3s.vm_balloon_mb)
      vm_disk_size_gb        = coalesce(try(node.vm_disk_size_gb, null), local.k3s.vm_disk_size_gb)
      secondary_disk_size_gb = coalesce(try(node.secondary_disk_size_gb, null), local.k3s.secondary_disk_size_gb)
      pci_devices            = coalesce(try(node.pci_devices, null), [])
      proxmox_tags           = coalesce(try(node.proxmox_tags, null), [])
    })
  ]

  vm_definitions = [
    for node_index, node in local.normalized_nodes : merge(
      {
        name                   = "k3s-node-${format("%02d", node_index + 1)}"
        target_node            = node.target_node
        vmid                   = local.k3s.node_vmid_start + node_index
        ci_user                = node.ci_user
        ansible_user           = node.ansible_user
        ip_address             = cidrhost(local.node_ip_subnet, local.node_ip_start_octet + node_index)
        ip_prefix_len          = local.k3s.ip_prefix_len
        vm_cores               = node.vm_cores
        vm_memory_mb           = node.vm_memory_mb
        vm_balloon_mb          = node.vm_balloon_mb
        vm_disk_size_gb        = node.vm_disk_size_gb
        secondary_disk_enabled = local.k3s.secondary_disk_enabled
        secondary_disk_size_gb = node.secondary_disk_size_gb
        proxmox_tags = distinct(concat(
          ["k3s-node"],
          node.proxmox_tags,
          length(node.pci_devices) > 0 ? ["gpu"] : []
        ))
        pci_devices = node.pci_devices
      },
      try(node.template_name, null) == null ? {} : { template_name = node.template_name },
      try(node.machine, null) == null ? {} : { machine = node.machine }
    )
  ]
}
