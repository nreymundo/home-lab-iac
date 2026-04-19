resource "local_file" "ansible_inventory" {
  filename = abspath("${path.module}/../../../ansible/inventories/k3s-nodes.yml")

  lifecycle {
    precondition {
      condition     = length(local.k3s.nodes) > 0
      error_message = "At least one node must be defined in local.k3s.nodes."
    }

    precondition {
      condition     = local.k3s.ip_prefix_len >= 8 && local.k3s.ip_prefix_len <= 30
      error_message = "local.k3s.ip_prefix_len must be between /8 and /30."
    }

    precondition {
      condition     = length(local.k3s.proxmox_nodes) > 0
      error_message = "At least one Proxmox node must be defined in local.k3s.proxmox_nodes."
    }

  }

  content = templatefile("${path.module}/templates/inventory.yaml.tpl", {
    nodes = [
      for node_index, vm in module.proxmox_vms.vms : {
        name         = vm.name
        ip           = vm.ip_address
        ansible_user = vm.ansible_user
        node_os      = vm.ci_user
        labels = merge(
          {
            "homelab.lan/role"            = "general"
            "homelab.lan/cpu-vendor"      = "intel"
            "homelab.lan/runtime"         = "vm"
            "homelab.lan/hypervisor"      = "proxmox"
            "homelab.lan/gpu"             = length(try(local.k3s.nodes[node_index].pci_devices, [])) > 0 ? "intel" : "none"
            "topology.kubernetes.io/zone" = vm.target_node
          },
          try(local.k3s.nodes[node_index].labels, {})
        )
      }
    ]
  })
}
